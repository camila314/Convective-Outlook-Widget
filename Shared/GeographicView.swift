import SwiftUI

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
    let features: [GeographicFeature]
    
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
            }.frame(width: geometry.size.width, height: geometry.size.height)
        }.aspectRatio(3/2, contentMode: .fit)
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
    
    return GeographicView(features: decoded.features + decoded2.features).background(Color.black)
}
