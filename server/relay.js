// Elephant Duel online relay.
// Pairs two players (quick match or a 4-letter room code) and forwards every message
// between them. The game itself runs on both players' machines in lockstep, so the
// server never needs to know the rules.
//
//   npm install
//   node relay.js            (listens on $PORT, default 8080)

const http = require("http");
const { WebSocketServer } = require("ws");

const PORT = process.env.PORT || 8080;
const LAG_MS = Number(process.env.LAG_MS || 0);   // testing only: delay every forwarded message
const rooms = new Map();      // code -> { players: [ws, ws?] }
let waiting = null;           // quick-match player waiting for an opponent

const server = http.createServer((req, res) => {
	// health check for the hosting service
	res.writeHead(200, { "content-type": "text/plain" });
	res.end("elephant duel relay ok\n");
});
const wss = new WebSocketServer({ server });

function send(ws, msg) {
	if (ws && ws.readyState === ws.OPEN) ws.send(JSON.stringify(msg));
}

function newCode() {
	const letters = "ABCDEFGHJKLMNPQRSTUVWXYZ";   // no I / O, easy to read out
	let code;
	do {
		code = Array.from({ length: 4 }, () => letters[Math.floor(Math.random() * letters.length)]).join("");
	} while (rooms.has(code));
	return code;
}

function start(code) {
	const room = rooms.get(code);
	room.players.forEach((ws, i) => send(ws, { t: "start", you: i, code }));
}

function leave(ws) {
	if (waiting === ws) waiting = null;
	const code = ws.room;
	if (!code || !rooms.has(code)) return;
	const room = rooms.get(code);
	room.players.forEach((p) => { if (p !== ws) { send(p, { t: "left" }); p.room = null; } });
	rooms.delete(code);
	ws.room = null;
}

wss.on("connection", (ws) => {
	ws.isAlive = true;
	ws.on("pong", () => { ws.isAlive = true; });
	ws.on("message", (data) => {
		let msg;
		try { msg = JSON.parse(data); } catch { return; }
		if (msg.t === "host") {
			leave(ws);
			const code = newCode();
			rooms.set(code, { players: [ws] });
			ws.room = code;
			send(ws, { t: "room", code });
		} else if (msg.t === "join") {
			leave(ws);
			const code = String(msg.code || "").toUpperCase();
			const room = rooms.get(code);
			if (!room) return send(ws, { t: "error", msg: "no_room" });
			if (room.players.length >= 2) return send(ws, { t: "error", msg: "full" });
			room.players.push(ws);
			ws.room = code;
			start(code);
		} else if (msg.t === "quick") {
			leave(ws);
			if (waiting && waiting !== ws && waiting.readyState === waiting.OPEN) {
				const code = newCode();
				rooms.set(code, { players: [waiting, ws] });
				waiting.room = code;
				ws.room = code;
				waiting = null;
				start(code);
			} else {
				waiting = ws;
				send(ws, { t: "waiting" });
			}
		} else if (msg.t === "leave") {
			leave(ws);
		} else if (ws.room && rooms.has(ws.room)) {
			// game traffic: pass straight to the other player
			for (const p of rooms.get(ws.room).players) {
				if (p === ws) continue;
				if (LAG_MS > 0) setTimeout(() => send(p, msg), LAG_MS);
				else send(p, msg);
			}
		}
	});
	ws.on("close", () => leave(ws));
});

// drop dead connections so rooms don't linger
setInterval(() => {
	for (const ws of wss.clients) {
		if (!ws.isAlive) { ws.terminate(); continue; }
		ws.isAlive = false;
		ws.ping();
	}
}, 15000);

server.listen(PORT, () => console.log("relay listening on " + PORT));
