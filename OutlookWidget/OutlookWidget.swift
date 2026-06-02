import WidgetKit
import SwiftUI
import Intents

struct OutlookEntry : TimelineEntry {
    let date: Date
    let convectiveData: [GeographicFeature]
}

struct OutlookView : View {
    let entry: OutlookEntry
    
    var geoView: some View {
        let url = Bundle.main.url(forResource:"us-states", withExtension:"geojson");
        let parsed = try! Data(contentsOf: url!)
        let decoded = try! JSONDecoder().decode(GeoJSON.self, from: parsed)

        let view = GeographicView(features: decoded.features + entry.convectiveData).frame(height: 170)
        if #available(macOSApplicationExtension 14.0, iOS 17.0, *) {
            return view.containerBackground(.black, for: .widget)
        } else {
            return view.background(Color.black)
        }
    }
    
    var body: some View {
        ZStack {
            geoView
            Text("Day 1")
                .foregroundColor(.white)
                .font(.system(size: 20))
                .padding(.leading, 0.0)
                .padding(.bottom, 20.0)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
        }
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
        // refresh every interval of :30
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

#Preview(as: .systemMedium) {
    OutlookWidget()
} timeline: {
    let url = Bundle.main.url(forResource:"us-states", withExtension:"geojson");
    let parsed = try! Data(contentsOf: url!)
    let decoded = try! JSONDecoder().decode(GeoJSON.self, from: parsed)

    let url2 = Bundle.main.url(forResource:"outlook_test", withExtension:"geojson");
    let parsed2 = try! Data(contentsOf: url2!)
    let decoded2 = try! JSONDecoder().decode(GeoJSON.self, from: parsed2)
    
    OutlookEntry(date: Date(), convectiveData: decoded.features + decoded2.features)
}
