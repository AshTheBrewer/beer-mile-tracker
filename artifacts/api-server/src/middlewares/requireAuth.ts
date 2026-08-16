import { getAuth } from "@clerk/express";
import type { Request, Response, NextFunction } from "express";
import { db, usersTable } from "@workspace/db";
import { eq } from "drizzle-orm";

export type UserRole = "super_admin" | "host" | "runner";

declare global {
  namespace Express {
    interface Request {
      userId?: string;
      userRole?: UserRole;
    }
  }
}

export const requireAuth = async (
  req: Request,
  res: Response,
  next: NextFunction,
): Promise<void> => {
  const auth = getAuth(req);
  const userId = auth?.userId;
  if (!userId) {
    res.status(401).json({ error: "Unauthorized" });
    return;
  }
  req.userId = userId;

  // Load role from DB
  const [user] = await db
    .select({ role: usersTable.role })
    .from(usersTable)
    .where(eq(usersTable.id, userId));

  req.userRole = (user?.role ?? "runner") as UserRole;
  next();
};

export const requireRole = (...roles: UserRole[]) => {
  return async (req: Request, res: Response, next: NextFunction): Promise<void> => {
    await requireAuth(req, res, () => {
      if (!req.userRole || !roles.includes(req.userRole)) {
        res.status(403).json({ error: "Forbidden" });
        return;
      }
      next();
    });
  };
};
