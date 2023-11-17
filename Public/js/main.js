function blobToJson(blob) {
    return new Promise((resolve, reject) => {
        let fr = new FileReader();
        fr.onload = () => {
            resolve(JSON.parse(fr.result));
        };
        fr.readAsText(blob);
    });
}

function uuidv4() {
    return ([1e7]+-1e3+-4e3+-8e3+-1e11).replace(/[018]/g, c => (c ^ crypto.getRandomValues(new Uint8Array(1))[0] & 15 >> c / 4).toString(16));
}

WebSocket.prototype.sendJsonBlob = function(data) {
    const string = JSON.stringify({ client: uuid, data: data })
    const blob = new Blob([string], {type: "application/json"});
    this.send(blob)
};

const uuid = uuidv4()
let ws = undefined

function WebSocketStart() {

    function getScaled2DContext(canvas) {
        const ctx = canvas.getContext('2d')
        const devicePixelRatio = window.devicePixelRatio || 1
        const backingStorePixelRatio = [
            ctx.webkitBackingStorePixelRatio,
            ctx.mozBackingStorePixelRatio,
            ctx.msBackingStorePixelRatio,
            ctx.oBackingStorePixelRatio,
            ctx.backingStorePixelRatio,
            1
        ].reduce((a, b) => a || b)

        const pixelRatio = devicePixelRatio / backingStorePixelRatio
        const rect = canvas.getBoundingClientRect();
        canvas.width = rect.width * pixelRatio;
        canvas.height = rect.height * pixelRatio;
        ctx.scale(pixelRatio, pixelRatio);
        return ctx;
    }

    function drawOnCanvas(ctx, x, y, color, isCatcher, isLocalPlayer) {
        ctx.beginPath();
        ctx.arc(x, y, 9, 0, 2 * Math.PI, false);
        ctx.fillStyle = color;
        ctx.fill();

        if ( isCatcher ) {
            ctx.beginPath();
            ctx.arc(x, y, 6, 0, 2 * Math.PI, false);
            ctx.fillStyle = 'black';
            ctx.fill();
        }

        if ( isLocalPlayer ) {
            ctx.beginPath();
            ctx.arc(x, y, 3, 0, 2 * Math.PI, false);
            ctx.fillStyle = 'white';
            ctx.fill();
        }
    }


    const canvas = document.getElementById('canvas')
    const ctx = getScaled2DContext(canvas);

    ws = new WebSocket("ws://" + window.location.host + "/channel")
    ws.onopen = () => {
        console.log("Socket is opened.");
        ws.sendJsonBlob({ connect: true })
    }

    ws.onmessage = (event) => {
        blobToJson(event.data).then((obj) => {
            ctx.clearRect(0, 0, canvas.width, canvas.height)
            for (var i in obj) {
                var p = obj[i]
                const isLocalPlayer = p.id.toLowerCase() == uuid
                drawOnCanvas(ctx, p.position.x, p.position.y, p.color, p.catcher, isLocalPlayer)
            }
        })
    };

    ws.onclose = () => {
        console.log("Socket is closed.");
        ctx.clearRect(0, 0, canvas.width, canvas.height)
    };

    document.onkeydown = () => {
        switch (event.keyCode) {
            case 38: ws.sendJsonBlob({ key: 'up', isPressed: true }); break;
            case 40: ws.sendJsonBlob({ key: 'down', isPressed: true }); break;
            case 37: ws.sendJsonBlob({ key: 'left', isPressed: true }); break;
            case 39: ws.sendJsonBlob({ key: 'right', isPressed: true }); break;
        }
    }

    document.onkeyup = () => {
        switch (event.keyCode) {
            case 38: ws.sendJsonBlob({ key: 'up', isPressed: false }); break;
            case 40: ws.sendJsonBlob({ key: 'down', isPressed: false }); break;
            case 37: ws.sendJsonBlob({ key: 'left', isPressed: false }); break;
            case 39: ws.sendJsonBlob({ key: 'right', isPressed: false }); break;
        }
    }
}

function WebSocketStop() {
    if ( ws !== undefined ) {
        ws.close()
    }
}
