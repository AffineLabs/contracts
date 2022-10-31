import crypto from "crypto";

process.stdout.write(crypto.randomBytes(32).toString("hex"));
