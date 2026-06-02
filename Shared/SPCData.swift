import SwiftUI


struct Query {
    let day: Int
}

class OutlookData: ObservableObject {
    // nil = loading, empty = error
    @Published var geoData: [GeographicFeature]? = nil
    @Published var forecast: String = ""
}

// why would u ever need this on a different thread
@MainActor
class SPCData {
    private let statesMap: GeoJSON
    private var tasks: [Task<(), Error>] = []
    private let timeout: Double?

    private var outlookDict: [Int: OutlookData] = [:]
    
    private func httpRequest(for url: String) async -> Data? {
        guard let urlProper = URL(string:url) else { return nil }
        
        var request = URLRequest(url: urlProper)
        if let interval = timeout {
            request.timeoutInterval = interval
        }
        request.httpMethod = "GET"
        
        guard let (data, _) = try? await URLSession.shared.data(for: request) else {
            return nil
        }
        return data
    }
    
    private func refreshOutlook(day: Int) async {
        guard let outlookData = outlookDict[day] else { return }
        
        outlookData.geoData = nil
        outlookData.forecast = ""
        
        guard
            let forecastData = await self.httpRequest(for: "https://www.spc.noaa.gov/products/outlook/day\(day)otlk.txt"),
            let geoData = await self.httpRequest(for: "https://www.spc.noaa.gov/products/outlook/day\(day)otlk_cat.nolyr.geojson")
        else {
            return
        }

        outlookData.forecast = String(data:forecastData, encoding: .utf8) ?? ""

        if let features = (try? JSONDecoder().decode(GeoJSON.self, from: geoData))?.features {
            outlookData.geoData = statesMap.features + features
        } else {
            outlookData.geoData = []
        }
    }
    
    private func taskForDay(day: Int) -> Task<(), Error> {
        // something something thread safety
        Task { @MainActor in
            await refreshOutlook(day: day)
            
            // we shall do our math in hours
            let intervals: [Double] = switch day {
            case 1:
                [1, 6, 13, 16.5, 20]
            case 2:
                [1, 17.5]
            case 3:
                [7.5, 21]
            default:
                []
            }

            var cal = Calendar(identifier: .gregorian)
            cal.timeZone = TimeZone.gmt

            var localZ: Double

            while !intervals.isEmpty {
                let now = Date()
                localZ = now.timeIntervalSince(cal.startOfDay(for: now)) / 3600
                let nextTime = intervals.first(where: { $0 > localZ }) ?? intervals[0] + 24
                
                do {
                    try await Task.sleep(for: .seconds((nextTime - localZ) * 3600))
                    await refreshOutlook(day: day)
                } catch {
                    break
                }
            }
        }
    }
    
    public init(day: Int? = nil, timeout: Double? = nil) {
        self.timeout = timeout

        // if any of this fails it's either my fault or apple's fault
        let statesMapData = try! Data(contentsOf: Bundle.main.url(forResource:"us-states", withExtension:"geojson")!)
        statesMap = try! JSONDecoder().decode(GeoJSON.self, from: statesMapData)
        
        if let onlyDay = day {
            outlookDict[onlyDay] = OutlookData()
            tasks.append(taskForDay(day: onlyDay))
        } else {
            for day in 1...4 {
                outlookDict[day] = OutlookData()
                tasks.append(taskForDay(day: day))
            }
        }
    }
    
    public func getOutlook(day: Int) -> OutlookData {
        self.outlookDict[day, default: OutlookData()]
    }
}
