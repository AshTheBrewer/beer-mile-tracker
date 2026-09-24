import { useEffect, useRef, type ReactNode } from 'react';
import { ClerkProvider, SignIn, SignUp, useClerk, useUser } from '@clerk/react';
import { publishableKeyFromHost } from '@clerk/react/internal';
import { neobrutalism } from '@clerk/themes';
import { QueryClient, QueryClientProvider, useQueryClient } from '@tanstack/react-query';
import { Route, Switch, Router as WouterRouter, useLocation, Redirect } from 'wouter';
import { useGetMe, useProvisionUser, getGetMeQueryKey } from '@workspace/api-client-react';
import { ErrorBoundary } from '@/components/error-boundary';
import { Toaster } from '@/components/ui/toaster';
import { TooltipProvider } from '@/components/ui/tooltip';
import { Page, SkeletonRows, StatePanel, ArrowLink } from '@/components/race-ui';
import { HomePage, EventsPage, JoinPage, EventDetailsPage } from '@/pages/public-pages';
import { DashboardPage, ProfilePage, NewEventPage, ManageEventPage, AdminPage } from '@/pages/portal-pages';
import NotFound from '@/pages/not-found';

const queryClient = new QueryClient({defaultOptions:{queries:{retry:1,staleTime:15000}}});
const clerkPubKey = publishableKeyFromHost(
  window.location.hostname,
  import.meta.env.VITE_CLERK_PUBLISHABLE_KEY,
);
const clerkProxyUrl = import.meta.env.VITE_CLERK_PROXY_URL;
const basePath = import.meta.env.BASE_URL.replace(/\/$/, '');
if (!clerkPubKey) throw new Error('Missing VITE_CLERK_PUBLISHABLE_KEY in .env file');

function stripBase(path: string): string {
  return basePath && path.startsWith(basePath)
    ? path.slice(basePath.length) || '/'
    : path;
}

const clerkAppearance = {
  theme: neobrutalism,
  cssLayerName: 'clerk',
  options: {
    logoPlacement: 'inside' as const,
    logoLinkUrl: basePath || '/',
    logoImageUrl: `${window.location.origin}${basePath}/logo.svg`,
    socialButtonsPlacement: 'bottom' as const,
  },
  variables: {
    colorPrimary: '#c44a2d', colorForeground: '#173e3d', colorMutedForeground: '#526761',
    colorDanger: '#b83726', colorBackground: '#f8f4e8', colorInput: '#f8f4e8',
    colorInputForeground: '#173e3d', colorNeutral: '#173e3d', fontFamily: "'DM Sans', sans-serif", borderRadius: '3px',
  },
  elements: {
    rootBox: 'w-full flex justify-center',
    cardBox: 'bg-[#f8f4e8] w-[460px] max-w-full overflow-hidden !rounded-sm !shadow-[8px_8px_0_#f8ba35]',
    card: '!shadow-none !border-0 !bg-transparent !rounded-none',
    footer: '!shadow-none !border-0 !bg-transparent !rounded-none',
    headerTitle: '!text-[#173e3d] !font-black',
    headerSubtitle: '!text-[#526761]',
    socialButtonsBlockButtonText: '!text-[#173e3d] !font-bold',
    formFieldLabel: '!text-[#173e3d] !font-bold',
    footerActionLink: '!text-[#c44a2d] !font-bold',
    footerActionText: '!text-[#526761]',
    dividerText: '!text-[#526761]',
    identityPreviewEditButton: '!text-[#c44a2d]',
    formFieldSuccessText: '!text-[#27705c]',
    alertText: '!text-[#173e3d]',
    logoBox: '!justify-start',
    logoImage: '!h-14 !w-auto',
    socialButtonsBlockButton: '!border-[#173e3d]/30 !bg-[#f8f4e8]',
    formButtonPrimary: '!bg-[#c44a2d] !text-[#f8f4e8] !font-black !uppercase',
    formFieldInput: '!border-[#b9b8a6] !bg-[#f8f4e8] !text-[#173e3d]',
    footerAction: '!bg-transparent',
    dividerLine: '!bg-[#b9b8a6]',
    alert: '!bg-[#f8ba35]/20',
    otpCodeFieldInput: '!text-[#173e3d]',
    formFieldRow: '!text-[#173e3d]',
    main: '!text-[#173e3d]',
  },
};

function ClerkQueryClientCacheInvalidator() {
  const { addListener } = useClerk();
  const client = useQueryClient();
  const previous = useRef<string | null | undefined>(undefined);
  useEffect(() => {
    const unsubscribe = addListener(({ user }) => {
      const id = user?.id ?? null;
      if (previous.current !== undefined && previous.current !== id) client.clear();
      previous.current = id;
    });
    return unsubscribe;
  }, [addListener, client]);
  return null;
}
function ProvisionSignedInUser() {
  const { isLoaded, isSignedIn, user } = useUser();
  const client = useQueryClient();
  const attempted = useRef<string | null>(null);
  const me = useGetMe({query:{enabled:!!isLoaded && !!isSignedIn,queryKey:getGetMeQueryKey(),retry:false}});
  const provision = useProvisionUser({mutation:{onSuccess:()=>client.invalidateQueries({queryKey:getGetMeQueryKey()})}});
  const mutate = provision.mutate;
  useEffect(() => {
    if (!isSignedIn || !user || !me.isError || (me.error as {status?:number})?.status !== 404 || attempted.current === user.id) return;
    attempted.current = user.id;
    mutate({data:{preferredName:user.firstName || user.fullName || undefined}});
  }, [isSignedIn,user?.id,me.isError,me.error,mutate]);
  if (provision.isError) return <div role="alert" className="fixed bottom-5 right-5 z-50 max-w-sm bg-[#f8f4e8] border-2 border-[#c44a2d] p-5 shadow-[5px_5px_0_#173e3d]"><strong className="display text-2xl">ACCOUNT SETUP PAUSED.</strong><p className="text-sm my-3">We couldn't finish setting up your race profile. Check your connection and retry.</p><button className="btn btn-primary" onClick={() => { attempted.current=null; provision.reset();me.refetch(); }}>Retry setup</button></div>;
  return null;
}
function Protected({children,role}: {children:ReactNode;role?:'host'|'super_admin'}) {
  const {isLoaded,isSignedIn}=useUser();
  const me=useGetMe({query:{enabled:!!isSignedIn,queryKey:getGetMeQueryKey(),retry:false}});
  if(!isLoaded) return <Page><div className="shell py-24"><SkeletonRows/></div></Page>;
  if(!isSignedIn) return <Redirect to="/sign-in"/>;
  if(me.isLoading || (me.isError && (me.error as {status?:number})?.status===404)) return <Page><div className="shell py-24"><SkeletonRows/></div></Page>;
  if(me.isError) return <Page><div className="shell py-24"><StatePanel title="Connection interrupted." detail="We couldn't load your account. Check your connection and try again." action={<button className="btn btn-primary" onClick={()=>me.refetch()}>Try again</button>}/></div></Page>;
  if(role && me.data?.role!==role && !(role==='host'&&me.data?.role==='super_admin')) return <Page><div className="shell py-24"><StatePanel title="Wrong lane." detail="You don't have access to this part of race control." action={<ArrowLink href="/dashboard">Go to dashboard</ArrowLink>}/></div></Page>;
  return <>{children}</>;
}
function AuthScreen({kind}:{kind:'in'|'up'}) {
  return <div className="min-h-[100dvh] grid lg:grid-cols-[.9fr_1.1fr]"><div className="bg-[#173e3d] text-[#f8f4e8] p-8 md:p-16 lg:p-20 flex flex-col justify-between"><a href={basePath||'/'} className="display text-3xl text-[#f8ba35]">BEERMILE / TRACKER</a><div className="my-20"><div className="eyebrow text-[#f8ba35] mb-7">The starting line is yours</div><h1 className="display text-[clamp(76px,8vw,126px)]">{kind==='in'?'BACK ON':'GET ON'}<br/><span className="text-[#f8ba35]">THE TRACK.</span></h1><p className="text-[#f8f4e8]/70 mt-7 max-w-md">Four laps. Four pours. One place to follow every second of it.</p></div><span className="eyebrow text-[#f8f4e8]/50">Chug / Run / Repeat</span></div><div className="bg-[#c44a2d] p-5 md:p-12 flex items-center justify-center">{kind==='in'?<SignIn routing="path" path={`${basePath}/sign-in`} signUpUrl={`${basePath}/sign-up`}/>:<SignUp routing="path" path={`${basePath}/sign-up`} signInUrl={`${basePath}/sign-in`}/>}</div></div>;
}
function RoutedErrorBoundary({children}:{children:ReactNode}) {const [location]=useLocation();return <ErrorBoundary resetKey={location}>{children}</ErrorBoundary>;}
function Routes() {
  return <RoutedErrorBoundary><Switch>
    <Route path="/" component={HomePage}/>
    <Route path="/events" component={EventsPage}/>
    <Route path="/events/:id" component={EventDetailsPage}/>
    <Route path="/join" component={JoinPage}/>
    <Route path="/dashboard">{<Protected><DashboardPage/></Protected>}</Route>
    <Route path="/profile">{<Protected><ProfilePage/></Protected>}</Route>
    <Route path="/host/events/new">{<Protected role="host"><NewEventPage/></Protected>}</Route>
    <Route path="/host/events/:id">{<Protected role="host"><ManageEventPage/></Protected>}</Route>
    <Route path="/admin">{<Protected role="super_admin"><AdminPage/></Protected>}</Route>
    <Route path="/sign-in/*?">{<AuthScreen kind="in"/>}</Route>
    <Route path="/sign-up/*?">{<AuthScreen kind="up"/>}</Route>
    <Route component={NotFound}/>
  </Switch></RoutedErrorBoundary>;
}
function ClerkProviderWithRoutes() {
  const [, setLocation] = useLocation();
  return <ClerkProvider publishableKey={clerkPubKey} proxyUrl={clerkProxyUrl} appearance={clerkAppearance} signInUrl={`${basePath}/sign-in`} signUpUrl={`${basePath}/sign-up`} localization={{signIn:{start:{title:'Back on the track',subtitle:'Sign in to see your races and results'}},signUp:{start:{title:'Get on the line',subtitle:'Make your next mile count'}}}} routerPush={(to)=>setLocation(stripBase(to))} routerReplace={(to)=>setLocation(stripBase(to),{replace:true})}>
    <QueryClientProvider client={queryClient}><TooltipProvider><ClerkQueryClientCacheInvalidator/><ProvisionSignedInUser/><Routes/><Toaster/></TooltipProvider></QueryClientProvider>
  </ClerkProvider>;
}
function App() {
  return <WouterRouter base={basePath}><ClerkProviderWithRoutes/></WouterRouter>;
}
export default App;