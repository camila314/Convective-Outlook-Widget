import WidgetKit
import SwiftUI
import Intents

struct OutlookEntry : TimelineEntry {
    let date: Date
    let convectiveData: [GeographicFeature]
}

struct OutlookView : View {
    let entry: OutlookEntry
    
    var body: some View {
        let url = Bundle.main.url(forResource:"us-states", withExtension:"geojson");
        let parsed = try! Data(contentsOf: url!)
        let decoded = try! JSONDecoder().decode(GeoJSON.self, from: parsed)

        GeographicView(features: decoded.features + entry.convectiveData, size: CGSize(width: 300, height: 140)).containerBackground(.black, for: .widget)
    }
}

func getOutlookData(timeout: Bool) async -> GeoJSON? {
    guard let url = URL(string: "https://www.spc.noaa.gov/products/outlook/day1otlk_cat.nolyr.geojson") else { return nil }

    var request = URLRequest(url: url)
    if timeout {
        request.timeoutInterval = 2
    }
    request.httpMethod = "GET"
    
    guard
        let (data, response) = try? await URLSession.shared.data(for: request),
        let decoded = try? JSONDecoder().decode(GeoJSON.self, from: data)
    else {
        return nil
    }
    return decoded
}

struct OutlookProvider : IntentTimelineProvider {
    func placeholder(in context: Context) -> OutlookEntry {
        OutlookEntry(date: Date(), convectiveData: [])
    }
    
    func getSnapshot(for configuration: ConfigurationIntent, in context: Context, completion: @escaping (OutlookEntry) -> Void) {
        // the real data happens here
        Task {
            let data = await getOutlookData(timeout: true)?.features ?? []
            completion(OutlookEntry(date: Date(), convectiveData: data))
        }
    }
    
    func getTimeline(for configuration: ConfigurationIntent, in context: Context, completion: @escaping (Timeline<OutlookEntry>) -> Void) {
        // refresh after 6 hours?
        Task {
            let data = await getOutlookData(timeout: false)?.features ?? []
            let entry = OutlookEntry(date: Date(), convectiveData: data)
            let timeline = Timeline(entries: [entry], policy: .after(Date().advanced(by: 3600 * 6)))
            completion(timeline)
        }
    }
    
    typealias Entry = OutlookEntry
}

struct OutlookWidget : Widget {
    var body: some WidgetConfiguration {
        IntentConfiguration(kind: "OutlookWidget", intent: ConfigurationIntent.self, provider: OutlookProvider()) { entry in OutlookView(entry: entry) }
            .configurationDisplayName("Convective Outlook")
            .description("Shows the daily Storm Prediction Center conective outlook")
            .supportedFamilies([.systemMedium])
    }
}
