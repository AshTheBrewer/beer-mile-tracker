import { Router, type IRouter } from "express";
import healthRouter from "./health";
import usersRouter from "./users";
import eventsRouter from "./events";
import registrationsRouter from "./registrations";
import lapLogsRouter from "./lapLogs";
import leaderboardRouter from "./leaderboard";
import adminRouter from "./admin";

const router: IRouter = Router();

router.use(healthRouter);
router.use(usersRouter);
router.use(eventsRouter);
router.use(registrationsRouter);
router.use(lapLogsRouter);
router.use(leaderboardRouter);
router.use(adminRouter);

export default router;
