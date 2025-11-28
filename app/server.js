const http = require('http');
const { Client } = require('pg');

// Debug: Display config at startup (visible in journalctl)
console.log("--- APP STARTUP ---");
console.log("DB_HOST:", process.env.DB_HOST);

const dbConfig = {
    user: 'postgres',
    host: process.env.DB_HOST,
    database: 'app_db',
    password: 'mypassword', // We keep this one
    port: 5432,
};

const server = http.createServer(async (req, res) => {
    res.setHeader('Access-Control-Allow-Origin', '*');
    res.setHeader('Content-Type', 'application/json');

    if (req.url === '/api/message') {
        // Critical check
        if (!process.env.DB_HOST) {
            res.statusCode = 500;
            return res.end(JSON.stringify({ error: "Configuration Error: DB_HOST is missing on server." }));
        }

        const client = new Client(dbConfig);
        try {
            await client.connect();
            const result = await client.query('SELECT content FROM messages LIMIT 1');
            res.end(JSON.stringify({
                message: result.rows[0].content,
                server: require('os').hostname()
            }));
        } catch (err) {
            console.error("DB Error:", err);
            res.statusCode = 500;
            res.end(JSON.stringify({ error: "DB Connection Failed", details: err.message }));
        } finally {
            await client.end();
        }
    } else {
        res.end(JSON.stringify({ status: "Ready" }));
    }
});

server.listen(3000, () => console.log('App running on 3000'));