import SwiftUI
import StoreKit

// for alerts, i like this better than having a trillion bools
// a little hacky because setting it to false does nothing but i address this
extension Binding where Value == Bool {
    static func mapped<T: Equatable>(_ binding: Binding<T>, to value: T) -> Binding<Bool> {
        Binding<Bool>(
            get: { binding.wrappedValue == value },
            set: {
                if $0 {
                    binding.wrappedValue = value
                }
            }
        )
    }
}

struct ColorKey: View {
    var label: String
    var color: Color

    var body: some View {
        HStack(spacing: 4) {
            Rectangle().fill(color).frame(width: 15, height: 15)
            Text(label)
            Spacer(minLength: 0)
        }
    }
    
    init(_ label: String, _ color: Color) {
        self.label = label
        self.color = color
    }
}

struct TickerButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundColor(Color.white)
            .font(.system(size: 30))
            // very important btw
            .opacity(configuration.isPressed || !isEnabled ? 0.4 : 1.0)
    }
}

// swiftui why do you do this to me
struct BasicKey: PreferenceKey {
    static var defaultValue: Bool = true
    static func reduce(value: inout Bool, nextValue: () -> Bool) {
        value = nextValue()
    }
}

// swiftui your synchronization systems confuse me a bit
struct OutlookGeographicView: View {
    @ObservedObject var outlook: OutlookData
    
    var body: some View {
        if let features = outlook.geoData {
            if features.isEmpty {
                GeometryReader { geometry in
                    Text("Failed to load!")
                        .font(.system(size: 30))
                        .padding()
                        .frame(width: geometry.size.width, height: geometry.size.height)
                }.aspectRatio(3/2, contentMode: .fit)
            } else {
                GeographicView(features: features)
            }
        } else {
            GeometryReader { geometry in
                Text("Loading...")
                    .font(.system(size: 30))
                    .padding()
                    .frame(width: geometry.size.width, height: geometry.size.height)
            }.aspectRatio(3/2, contentMode: .fit)
        }
    }
}
struct OutlookForecastView: View {
    @ObservedObject var outlook: OutlookData
    
    var body: some View {
        Text(outlook.forecast)
            .frame(minHeight: 500)
            .padding(.top, 1.0)
            .padding(.bottom, 30.0)
            .monospaced()
            .font(.system(size: 13))
            .fontWeight(.bold)
    }
}

// views are main actor by default but xcode wants to be silly
@MainActor
struct ContentView: View {
    static let colors: [Color] = [
        Color(red: 0.22, green: 0.24, blue: 0.3),
        .black
    ]
    
    @State private var spc = SPCData()

    @State private var day: Int = 1
    @State private var scrollToTop: Bool = true

    // cutesy
    @State private var spinHeart: Bool = false
    @State private var fillHeart: Bool = false
    @State private var heartPopup: Bool = false

    @State private var tipPressed: Bool = false
    @State private var tipError: Bool = false
    @State private var tipSuccess: Bool = false
    
    // settings
    @AppStorage("showLocation") var showLocation: Bool = false
    
    enum AlertState {
        case none
        case heartPressed
        case tipPressed
        case tipSuccess
        case tipError
    }
    @State var alertState: AlertState = .none

    @AppStorage("pressHeart") var pressHeart: Bool = false
    @AppStorage("timesOpened") var timesOpened: Int = 0
    
    var body: some View {
        return NavigationStack {
            VStack(spacing: 0) {
                HStack {
                    Button(action: {
                        self.alertState = .heartPressed
                        self.pressHeart = true
                    }, label: {
                        Image(systemName: fillHeart ? "heart.fill" : "heart")
                            .font(.title)
                            .foregroundColor(Color.pink)
                            .padding()
                            .rotationEffect(.degrees(spinHeart ? 360 : 0))
                            .animation(fillHeart ? .easeIn(duration: 0.5) : .easeOut(duration: 0.5), value: fillHeart)
                            .animation(.bouncy(duration: 1), value: spinHeart)
                            .onAppear { timesOpened += 1 }
                            .task {
    #if targetEnvironment(simulator)
                                let doThis = true
    #else
                                let doThis = timesOpened > 3 && !pressHeart
    #endif
                                
                                if doThis {
                                    try? await Task.sleep(for: .seconds(3))
                                    
                                    fillHeart = true
                                    try? await Task.sleep(for: .seconds(0.25))
                                    spinHeart = true
                                    try? await Task.sleep(for: .seconds(0.75))
                                    fillHeart = false
                                }
                            }
                    })
                    
                    Spacer()

                    NavigationLink(destination: SettingsView()) {
                        Image(systemName: "gear")
                            .font(.title)
                            .foregroundColor(.white)
                            .padding()
                    }
                }
                .background(ContentView.colors[0])
                .frame(height: 65)
                alerts
                scrollBody
            }
            .background(scrollToTop ? ContentView.colors[0] : Color.black)
            .navigationTitle("")
            #if os(iOS)
            .navigationBarHidden(true)
            #else
            .toolbar(.hidden)
            #endif
        }
        .preferredColorScheme(.dark)
    }
    
    private func tipTask(product: String) {
        Task {
            guard
                let product = try? await Product.products(for: [product]).first,
                let result = try? await product.purchase()
            else {
                alertState = .tipError
                return
            }
            switch result {
             case .success(let result):
                if case .verified(let transaction) = result {
                    await transaction.finish()
                }
                // it's fine i guess
                if case .unverified(let transaction, _) = result {
                    await transaction.finish()
                }
                alertState = .tipSuccess
                break
             default:
                alertState = .none
                break
             }
        }
    }

    private var alerts: some View {
        ZStack {
            Color.clear
                .frame(height: 0)
                .alert("Do you like my app?", isPresented: .mapped($alertState, to: .heartPressed)) {
                    VStack {
                        Button("Tip me!") { alertState = .tipPressed }
                        Button("Write a review") { Task { await UIApplication.shared.open(URL(string:"https://google.com/")!) } }
                        Button("Contact me") { Task { await UIApplication.shared.open(URL(string:"mailto:ilaca314@gmail.com")!) } }
                        Button("Cancel", role: .cancel) { alertState = .none }
                    }
                } message: {
                    Text("""
                I worked pretty hard on this app and \
                I publish it for free out of my own pocket. \
                I would really appreciate if you could leave a tip \
                or a review if you like it. Thank you!
                """)
                }
            Color.clear
                .frame(height: 0)
                .alert("Tip Options", isPresented: .mapped($alertState, to: .tipPressed)) {
                    Button("Small Tip: $1") { tipTask(product: "small_tip") }
                    Button("Medium Tip: $5") { tipTask(product: "medium_tip") }
                    Button("Huge Tip: $20") { tipTask(product: "huge_tip") }
                    Button("Cancel", role: .cancel) { alertState = .none }
                }
            Color.clear
                .frame(height: 0)
                .alert("Tip Error", isPresented: .mapped($alertState, to: .tipError)) {
                    Button("Close") { alertState = .none }
                } message: {
                    Text("Failed to load the purchase. Try again later!")
                }
            Color.clear
                .frame(height: 0)
                .alert("Thank you!", isPresented: .mapped($alertState, to: .tipSuccess)) {
                    Button("Close") { alertState = .none }
                } message: {
                    Text("Thank you so much for tipping! I appreciate your support <3")
                }
        }
    }

    private var scrollBody: some View {
        ScrollView(showsIndicators: false) {
            // all this to make colors not weird in the bg
            GeometryReader { proxy in
                Color.clear
                    .preference(
                        key: BasicKey.self,
                        value: proxy.frame(in: .global).minY > 0
                    )
            }.onPreferenceChange(BasicKey.self) {
                scrollToTop = $0
            }.frame(height: 10)
            
            VStack {
                HStack {
                    Button(action: {
                        self.day = max(self.day - 1, 1)
                    }, label: { Image(systemName:"chevron.left") })
                    .buttonStyle(TickerButtonStyle())
                    .disabled(self.day <= 1)
                    Spacer(minLength: 0)
                    Text("Convective Outlook Day \(self.day)")
                        .font(.system(size: 25))
                    Spacer(minLength: 0)
                    Button(action: {
                        self.day = min(self.day + 1, 3)
                    }, label: { Image(systemName:"chevron.right") })
                    .buttonStyle(TickerButtonStyle())
                    .disabled(self.day >= 3)
                }
                .frame(height: 40)
                .padding(.horizontal, 15.0)
                
                /*Picker(selection: .constant(1), label: Text("Picker")) {
                    Text("Cat.").tag(1)
                    Text("Tornado").tag(2)
                    Text("Wind").tag(3)
                    Text("Hail").tag(4)
                }
                .pickerStyle(.segmented)*/
                OutlookGeographicView(outlook: spc.getOutlook(day: day))
                HStack {
                    ColorKey("Storms", Color(red: 0.7, green: 1, blue: 0.7))
                    Spacer(minLength: 0)
                    ColorKey("Slight", Color(red: 1, green: 1, blue: 0))
                    Spacer(minLength: 0)
                    ColorKey("Moderate", Color(red: 1, green: 0, blue: 0))
                }
                HStack {
                    ColorKey("Marginal", Color(red: 0, green: 0.7, blue: 0))
                    Spacer(minLength: 0)
                    ColorKey("Enhanced", Color(red: 1, green: 0.5, blue: 0))
                    Spacer(minLength: 0)
                    ColorKey("High", Color(red: 1, green: 0, blue: 1))
                }
                
                HStack {
                    Text("Forecast Discussion")
                        .font(.title2)
                        .fontWeight(.semibold)
                        .underline()
                    Spacer()
                }.padding(.top)
                
                OutlookForecastView(outlook: spc.getOutlook(day: day))
            }
            .padding(.horizontal, 15.0)
            .background(GeometryReader { geo in
                LinearGradient(
                    colors: ContentView.colors,
                    startPoint: .top,
                    endPoint: UnitPoint(x: 0.5, y: 350 / geo.size.height)
                )
            })
        }
        .ignoresSafeArea(edges: .bottom)
    }
    
}

#Preview {
    ContentView()
}
