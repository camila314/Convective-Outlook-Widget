import SwiftUI
import CoreLocation

// oh macOS 13, how I love you macOS 13
@MainActor
class LocationManager: NSObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private var continuation: AsyncStream<CLLocation>.Continuation?
    private var permissionContinuation: CheckedContinuation<CLAuthorizationStatus, Never>?

    var locations: AsyncStream<CLLocation> {
        AsyncStream { continuation in
            self.continuation = continuation
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        locations.forEach { continuation?.yield($0) }
    }
    
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        guard let continuation = permissionContinuation else { return }
    
        if manager.authorizationStatus != .notDetermined {
            permissionContinuation = nil
            continuation.resume(returning: manager.authorizationStatus)
        }
    }
    
    func request() async -> CLAuthorizationStatus {
        guard manager.authorizationStatus == .notDetermined else {
            return manager.authorizationStatus
        }
        
        return await withCheckedContinuation { continuation in
            self.permissionContinuation = continuation
            manager.requestWhenInUseAuthorization()
        }
    }
    
    private override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyThreeKilometers
        manager.requestWhenInUseAuthorization()
        manager.startUpdatingLocation()
    }
    
    static let shared = LocationManager()
}

struct GeographicFeature: Decodable {
    let label: String?

    var stroke: Color {
        switch label {
        case "TSTM": return Color(red: 0.7, green: 1, blue: 0.7)
        case "MRGL": return Color(red: 0, green: 0.7, blue: 0)
        case "SLGT": return Color(red: 1, green: 1, blue: 0)
        case "ENH": return Color(red: 1, green: 0.5, blue: 0)
        case "MDT": return Color(red: 1, green: 0, blue: 0)
        case "HIGH": return Color(red: 1, green: 0, blue: 1)
        default: return Color(red: 0.8, green: 0.8, blue: 0.8)
        }
    }

    var line: Double {
        if label != nil {
            1.5
        } else {
            0.5
        }
    }

    let geometry: Geometry

    enum Geometry: Decodable {
        case point(coordinates: [Double])
        case multiPoint(coordinates: [[Double]])
        case lineString(coordinates: [[Double]])
        case multiLineString(coordinates: [[[Double]]])
        case polygon(coordinates: [[[Double]]])
        case multiPolygon(coordinates: [[[[Double]]]])

        private enum CodingKeys: String, CodingKey {
            case type, coordinates
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            let type = try container.decode(String.self, forKey: .type)
            switch type {
            case "Point":
                self = .point(coordinates: try container.decode([Double].self, forKey: .coordinates))
            case "MultiPoint":
                self = .multiPoint(coordinates: try container.decode([[Double]].self, forKey: .coordinates))
            case "LineString":
                self = .lineString(coordinates: try container.decode([[Double]].self, forKey: .coordinates))
            case "MultiLineString":
                self = .multiLineString(coordinates: try container.decode([[[Double]]].self, forKey: .coordinates))
            case "Polygon":
                self = .polygon(coordinates: try container.decode([[[Double]]].self, forKey: .coordinates))
            case "MultiPolygon":
                self = .multiPolygon(coordinates: try container.decode([[[[Double]]]].self, forKey: .coordinates))
            default:
                throw DecodingError.dataCorruptedError(forKey: .type, in: container, debugDescription: "Unknown geometry type: \(type)")
            }
        }
    }

    private enum CodingKeys: String, CodingKey {
        case geometry, properties
    }

    private enum PropertiesKeys: String, CodingKey {
        case label = "LABEL"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let propertiesContainer = try container.nestedContainer(keyedBy: PropertiesKeys.self, forKey: .properties)
        label = try propertiesContainer.decodeIfPresent(String.self, forKey: .label)
        geometry = try container.decode(Geometry.self, forKey: .geometry)
    }
}

struct GeoJSON: Decodable {
    let features: [GeographicFeature]
}

// Mercator for now
func project(_ lon: Double, _ lat: Double, _ size: CGSize) -> CGPoint {
    // US bounding box
    let minLon = -127.0, maxLon = -65.0
    let minLat =   24.0, maxLat =  50.0

    func mercatorY(_ lat: Double) -> Double {
        let r = lat * .pi / 180
        return log(tan(r) + 1 / cos(r))
    }

    let rawMinX = (minLon + 180) / 360
    let rawMaxX = (maxLon + 180) / 360
    let rawMinY = (1 - mercatorY(maxLat) / .pi) / 2
    let rawMaxY = (1 - mercatorY(minLat) / .pi) / 2

    let normX  = (lon + 180) / 360
    let normY  = (1 - mercatorY(lat) / .pi) / 2

    let usWidth  = rawMaxX - rawMinX
    let usHeight = rawMaxY - rawMinY

    let scaleX = size.width  / usWidth
    let scaleY = size.height / usHeight
    let scale  = min(scaleX, scaleY)

    let offsetX = (size.width  - usWidth  * scale) / 2
    let offsetY = (size.height - usHeight * scale) / 2

    let x = (normX - rawMinX) * scale + offsetX
    let y = (normY - rawMinY) * scale + offsetY

    return CGPoint(x: x, y: y)
}

struct GeographicView: View {
    @AppStorage("showLocation") var showLocation: Bool = false

    let features: [GeographicFeature]
    @State var location: CLLocationCoordinate2D?
    
    var body: some View {
        GeometryReader { geometry in
            Canvas { context, size in
                // Draw the view
                for feature in features {
                    switch feature.geometry {
                    case let .polygon(coordinates):
                        drawPoly(coordinates, stroke: feature.stroke, line: feature.line, ctx: context, size: size)
                    case let .multiPolygon(coordinates):
                        for poly in coordinates {
                            drawPoly(poly, stroke: feature.stroke, line: feature.line, ctx: context, size: size)
                        }
                    default:
                        break
                    }
                }
                
                if showLocation {
                    if let globalCoord = location {
                        let coord = project(globalCoord.longitude, globalCoord.latitude, size)
                        let circle = Path(ellipseIn: CGRect(x: coord.x - 3, y: coord.y - 3, width: 6, height: 6))
                        context.fill(circle, with: .color(Color(red: 0.3, green: 0.75, blue: 1.0)))
                    }
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .task {
                for await loc in LocationManager.shared.locations {
                    location = loc.coordinate
                }
            }
        }
        .aspectRatio(3/2, contentMode: .fit)
    }
    
    func drawPoly(_ poly: [[[Double]]], stroke: Color, line: Double, ctx: GraphicsContext, size: CGSize) {
        for ring in poly {
            var path = Path()
            for (i, point) in ring.enumerated() {
                guard point.count >= 2 else { continue }
                let projected = project(point[0], point[1], size)
                i == 0 ? path.move(to: projected) : path.addLine(to: projected)
            }
            path.closeSubpath()
            ctx.stroke(path, with: .color(stroke), lineWidth: line)
        }
    }
}


#Preview {
    let url = Bundle.main.url(forResource:"us-states", withExtension:"geojson");
    let parsed = try! Data(contentsOf: url!)
    let decoded = try! JSONDecoder().decode(GeoJSON.self, from: parsed)

    let url2 = Bundle.main.url(forResource:"outlook_test", withExtension:"geojson");
    let parsed2 = try! Data(contentsOf: url2!)
    let decoded2 = try! JSONDecoder().decode(GeoJSON.self, from: parsed2)
    
    return GeographicView(features: decoded.features + decoded2.features, location: CLLocationCoordinate2D(latitude: 37.323, longitude: -122.0322)).background(Color.black)
}
