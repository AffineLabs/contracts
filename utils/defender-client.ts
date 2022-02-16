import { AdminClient } from 'defender-admin-client';

const defenderAPIKey = process.env.DEFENDER_API_KEY || "";
const defenderAPISecret = process.env.DEFENDER_API_SECRET || "";

const defenderClient = new AdminClient({apiKey: defenderAPIKey, apiSecret: defenderAPISecret});

export default defenderClient;