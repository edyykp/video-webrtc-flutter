const io = require("socket.io")(3000, {
  cors: { origin: "*" },
});

const ROOM_ID = 'camera_101'; // Fixed room for telemedicine consultations
const activeUsers = [];

io.on("connection", (socket) => {
  console.log("[CONNECT] Utilizator conectat:", socket.id);

  // Alăturarea în camera de consultație fixă
  socket.on("join", () => {
    if (!activeUsers.includes(socket.id)) {
      activeUsers.push(socket.id);
    }

    socket.join(ROOM_ID);
    console.log(`[JOIN] ${socket.id} a intrat in camera: ${ROOM_ID}`);
    console.log(`[ROOM] ${ROOM_ID} are ${activeUsers.length} utilizatori`);

    if (activeUsers.length === 2) {
      const firstPeer = activeUsers.find((id) => id !== socket.id);
      if (firstPeer) {
        console.log(`[READY] Notific pe primul peer ${firstPeer} să trimită ofertă`);
        io.to(firstPeer).emit("ready");
      }
    }
  });

  // Transmiterea Ofertei/Răspunsului SDP și ICE Candidates
  socket.on("message", (data) => {
    console.log(`[MESSAGE] ${socket.id} -> ${ROOM_ID} : ${data.payload?.type}`);
    socket.to(ROOM_ID).emit("message", data.payload);
  });

  socket.on("disconnect", () => {
    console.log("[DISCONNECT] Utilizator deconectat:", socket.id);
    const index = activeUsers.indexOf(socket.id);
    if (index !== -1) {
      activeUsers.splice(index, 1);
    }
    console.log(`[ROOM] ${ROOM_ID} are ${activeUsers.length} utilizatori`);
  });

});

const PORT = process.env.PORT || 3000;
console.log(`Server de signaling WebRTC pornit pe portul ${PORT}`);
console.log("Așteptând conexiuni de la aplicații Flutter...");
