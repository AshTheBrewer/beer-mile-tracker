import express, { type Express } from "express";
import cors from "cors";
import pinoHttp from "pino-http";
import { clerkMiddleware } from "@clerk/express";
import { publishableKeyFromHost } from "@clerk/shared/keys";
import {
  CLERK_PROXY_PATH,
  clerkProxyMiddleware,
  getClerkProxyHost,
} from "./middlewares/clerkProxyMiddleware";
import router from "./routes";
import { logger } from "./lib/logger";

const app: Express = express();

app.use(
  pinoHttp({
    logger,
    serializers: {
      req(req) {
        return {
          id: req.id,
          method: req.method,
          url: req.url?.split("?")[0],
        };
      },
      res(res) {
        return {
          statusCode: res.statusCode,
        };
      },
    },
  }),
);

app.use(CLERK_PROXY_PATH, clerkProxyMiddleware());

// Allow credentialed requests only from explicitly trusted origins.
// Mobile (Flutter) native requests have no Origin header and are permitted unconditionally.
// Unknown browser origins receive non-credentialed CORS or are blocked.
const buildAllowedOrigins = (): Set<string> => {
  const origins = new Set<string>();
  // Replit dev/preview domain(s)
  const replitDomains = process.env.REPLIT_DOMAINS ?? "";
  for (const d of replitDomains.split(",").filter(Boolean)) {
    origins.add(`https://${d.trim()}`);
  }
  const devDomain = process.env.REPLIT_DEV_DOMAIN ?? "";
  if (devDomain) origins.add(`https://${devDomain}`);
  // Localhost for local dev tooling
  for (const port of [3000, 5173, 8080, 8081]) {
    origins.add(`http://localhost:${port}`);
  }
  return origins;
};
const allowedOrigins = buildAllowedOrigins();

app.use(
  cors({
    credentials: true,
    origin: (origin, callback) => {
      // No-origin requests (Flutter native, curl, server-to-server) are allowed.
      if (!origin) return callback(null, true);
      if (allowedOrigins.has(origin)) return callback(null, true);
      // Unknown browser origin: allow request but without credentials.
      return callback(null, false);
    },
  }),
);
app.use(express.json());
app.use(express.urlencoded({ extended: true }));

app.use(
  clerkMiddleware((req) => ({
    publishableKey: publishableKeyFromHost(
      getClerkProxyHost(req) ?? "",
      process.env.CLERK_PUBLISHABLE_KEY,
    ),
  })),
);

app.use("/api", router);

export default app;
