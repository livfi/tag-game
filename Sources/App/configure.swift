import Vapor
import Foundation

open class WebSocketClient {
    open var id: UUID
    open var socket: WebSocket    

    init(id: UUID, socket: WebSocket) {
        self.id = id
        self.socket = socket
    }
}

open class WebSocketClients {
    var eventLoop: EventLoop
    var storage: [UUID: WebSocketClient]

    var active: [WebSocketClient] {
        self.storage.values.filter { !$0.socket.isClosed }
    }

    init(eventLoop: EventLoop, clients: [UUID: WebSocketClient] = [:]) {
        self.eventLoop = eventLoop
        self.storage = clients
    }

    func add(_ client: WebSocketClient) {
        self.storage[client.id] = client
    }

    func remove(_ client: WebSocketClient) {
        self.storage[client.id] = nil
    }

    func find(_ uuid: UUID) -> WebSocketClient? {
        self.storage[uuid]
    }

    deinit {
        let futures = self.storage.values.map{ $0.socket.close() }
        try! self.eventLoop.flatten(futures).wait()
    }
}

struct WebsocketMessage<T: Codable>: Codable {
    let client: UUID
    let data: T
}

extension ByteBuffer {
    func decodeWebsocketMessage<T: Codable>(_ type: T.Type) -> WebsocketMessage<T>? {
        try? JSONDecoder().decode(WebsocketMessage<T>.self, from: self)
    }
}

struct Connect: Codable {
    let connect: Bool
}

final class PlayerClient: WebSocketClient {
    struct Status: Codable {
        var id: UUID!
        var position: Point
        var color: String
        var catcher: Bool = false
        var speed = 4
    }

    var status: Status
    var upPressed: Bool = false
    var downPressed: Bool = false
    var leftPressed: Bool = false
    var rightPressed: Bool = false

    public init(id: UUID, socket: WebSocket, status: Status) {
        self.status = status
        self.status.id = id

        super.init(id: id, socket: socket)
    }

    func update(_ input: Input) {
        switch input.key {
        case .up:
            self.upPressed = input.isPressed
        case .down:
            self.downPressed = input.isPressed
        case .left:
            self.leftPressed = input.isPressed
        case .right:
            self.rightPressed = input.isPressed
        }
    }

    func updateStatus() {
        if self.upPressed {
            self.status.position.y = max(0, self.status.position.y - self.status.speed)
        }
        if self.downPressed {
            self.status.position.y = min(480, self.status.position.y + self.status.speed)
        }
        if self.leftPressed {
            self.status.position.x = max(0, self.status.position.x - self.status.speed)
        }
        if self.rightPressed {
            self.status.position.x = min(640, self.status.position.x + self.status.speed)
        }
    }
}

class GameSystem {
    var clients: WebSocketClients

    var timer: DispatchSourceTimer
    var timeout: DispatchTime?
        
    init(eventLoop: EventLoop) {
        self.clients = WebSocketClients(eventLoop: eventLoop)

        self.timer = DispatchSource.makeTimerSource()
        self.timer.setEventHandler { [unowned self] in
            self.notify()
        }
        self.timer.schedule(deadline: .now() + .milliseconds(20), repeating: .milliseconds(20))
        self.timer.activate()
    }

    func randomRGBAColor() -> String {
        let range = (0..<255)
        let r = range.randomElement()!
        let g = range.randomElement()!
        let b = range.randomElement()!
        return "rgba(\(r), \(g), \(b), 1)"
    }

    func connect(_ ws: WebSocket) {
        ws.onBinary { [unowned self] ws, buffer in
            if let msg = buffer.decodeWebsocketMessage(Connect.self) {
                let catcher = self.clients.storage.values
                    .compactMap { $0 as? PlayerClient }
                    .filter { $0.status.catcher }
                    .isEmpty

                let player = PlayerClient(id: msg.client,
                                          socket: ws,
                                          status: .init(position: .init(x: 0, y: 0),
                                                        color: self.randomRGBAColor(),
                                                        catcher: catcher))
                self.clients.add(player)
            }

            if
                let msg = buffer.decodeWebsocketMessage(Input.self),
                let player = self.clients.find(msg.client) as? PlayerClient
            {
                player.update(msg.data)
            }
        }
    }

    func notify() {
        if let timeout = self.timeout {
            let future = timeout + .seconds(2)
            if future < DispatchTime.now() {
                self.timeout = nil
            }
        }

        let players = self.clients.active.compactMap { $0 as? PlayerClient }
        guard !players.isEmpty else {
            return
        }

        let gameUpdate = players.map { player -> PlayerClient.Status in
            player.updateStatus()
            
            players.forEach { otherPlayer in
                guard
                    self.timeout == nil,
                    otherPlayer.id != player.id,
                    (player.status.catcher || otherPlayer.status.catcher),
                    otherPlayer.status.position.distance(player.status.position) < 18
                else {
                    return
                }
                self.timeout = DispatchTime.now()
                otherPlayer.status.catcher = !otherPlayer.status.catcher
                player.status.catcher = !player.status.catcher
            }
            return player.status
        }
        let data = try! JSONEncoder().encode(gameUpdate)
        players.forEach { player in
            player.socket.send([UInt8](data))
        }
    }
    
    deinit {
        self.timer.setEventHandler {}
        self.timer.cancel()
    }
}

struct Input: Codable {

    enum Key: String, Codable {
        case up
        case down
        case left
        case right
    }

    let key: Key
    let isPressed: Bool
}

struct Point: Codable {
    var x: Int = 0
    var y: Int = 0
    
    func distance(_ to: Point) -> Float {
        let xDist = Float(self.x - to.x)
        let yDist = Float(self.y - to.y)
        return sqrt(xDist * xDist + yDist * yDist)
    }
}

// configures your application
public func configure(_ app: Application) async throws {
    // uncomment to serve files from /Public folder
    app.middleware.use(FileMiddleware(publicDirectory: app.directory.publicDirectory))

    let gameSystem = GameSystem(eventLoop: app.eventLoopGroup.next())

    app.webSocket("channel") { req, ws in
        gameSystem.connect(ws)
    }
    
    app.get { req in
        req.view.render("index.html")
    }
}
