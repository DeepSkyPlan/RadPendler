import MapKit
import SwiftUI

/// MKMapView wrapper: SwiftUI's `Map` cannot show tile overlays, and the radar is one.
struct RouteMapView: UIViewRepresentable {
    var options: [TripOption]
    var selectedID: TripOption.ID?
    var radarFrames: [Date]
    /// Frame on screen; nil hides the radar.
    var radarTime: Date?
    /// Only while the frames are being played does it pay to hold the
    /// neighbours ready. Standing still on one minute, two extra tile layers
    /// are two extra downloads of a picture nobody is going to look at.
    var radarPreload = false
    /// Fixed points from the settings, drawn as flags.
    var waypoints: [Place] = []
    /// Start und Ziel, für die Sekunden **vor** der ersten Route. Ohne das
    /// steht die Karte beim Öffnen auf halb Europa: man sieht eine Karte und
    /// erkennt nichts darauf — und weil die Kästen sich jetzt nacheinander
    /// füllen, dauert dieser Zustand sichtbar länger als früher.
    var ends: [CLLocationCoordinate2D] = []
    /// The way actually ridden, coloured by speed. Grows point by point while
    /// a ride is being recorded and stands still afterwards.
    var track: [RidePoint] = []
    /// Where the ride stood still, and whether that was a red light.
    var trackStops: [RideStop] = []
    /// Lit junctions to show while riding — the planned route's and the ones
    /// this rider has learned. Afterwards one can see where one stood; ahead
    /// of time one wants to see what is coming.
    var signals: [CLLocationCoordinate2D] = []
    /// Die Linie, der **gerade** gefolgt wird. Während einer Fahrt ist das
    /// nicht die Linie der Möglichkeit: wird unterwegs neu geplant, ändert
    /// sich der Weg, und die Karte muss den neuen zeigen — sonst zeigt der
    /// Pfeil auf eine Straße, die auf der Karte nicht eingezeichnet ist.
    var guidedLine: [CLLocationCoordinate2D] = []
    /// Die Linie, die einmal geplant war: dünn und grau daneben. Während einer
    /// Fahrt nach einer Neuplanung, hinterher neben der gefahrenen.
    var plannedLine: [CLLocationCoordinate2D] = []
    /// Where the rider is now; drawn as a heading arrow, not as a pin.
    var rider: CLLocationCoordinate2D? = nil
    /// Degrees from north, negative when unknown.
    var course: CLLocationDirection = -1
    /// Keep the map on the rider instead of on the whole route.
    var following = false
    /// Gesetzt, solange der Fahrer neben der Route ist: dann folgt die Karte
    /// ihm nicht mehr eng, sondern nimmt beides ins Bild — wo er ist und wo
    /// die Route liegt. Und sie steht dabei nach Norden: auf einer Karte, die
    /// sich mitdreht, ist „dort drüben liegt die Route" schwerer zu lesen als
    /// ein Pfeil auf einer, die still steht.
    var showBoth: CLLocationCoordinate2D? = nil
    /// The user dragged the map: following has to give way to the hand.
    var onPan: (() -> Void)? = nil
    /// Keeps MapKit's own controls — the compass above all — out from under
    /// whatever the app floats over the top of the map.
    var topInset: CGFloat = 0
    /// Tap on an option's label on the map.
    var onSelect: ((TripOption.ID) -> Void)? = nil

    func makeUIView(context: Context) -> MKMapView {
        let map = MKMapView()
        map.delegate = context.coordinator
        map.pointOfInterestFilter = .excludingAll
        map.showsCompass = true
        map.register(MKMarkerAnnotationView.self, forAnnotationViewWithReuseIdentifier: "pin")
        map.register(OptionLabelView.self, forAnnotationViewWithReuseIdentifier: "label")
        map.register(SignalDotView.self, forAnnotationViewWithReuseIdentifier: "signal")
        map.register(StopDotView.self, forAnnotationViewWithReuseIdentifier: "stop")
        map.register(RiderView.self, forAnnotationViewWithReuseIdentifier: "rider")
        let press = UILongPressGestureRecognizer(target: context.coordinator,
                                                 action: #selector(Coordinator.handleLongPress(_:)))
        press.minimumPressDuration = 0.45
        map.addGestureRecognizer(press)
        // Rides alongside MapKit's own recognisers instead of replacing them:
        // it only has to notice that a hand was on the map, so the camera can
        // stop fighting it.
        let pan = UIPanGestureRecognizer(target: context.coordinator,
                                         action: #selector(Coordinator.handlePan(_:)))
        pan.delegate = context.coordinator
        map.addGestureRecognizer(pan)
        return map
    }

    func updateUIView(_ map: MKMapView, context: Context) {
        context.coordinator.update(map, self)
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class LegLine: MKPolyline {
        var kind: LegKind = .walk
        var emphasized = true
        /// Belongs to a trip that misses the fixed points.
        var dimmed = false
    }

    /// Die Linie, der gerade gefolgt wird, und die, die einmal geplant war.
    /// Eigene Klasse, damit sie nicht mit den Linien der Möglichkeiten
    /// zusammen gelöscht wird: die eine ändert sich mit jeder Neuplanung, die
    /// anderen nur mit einem neuen Plan.
    final class GuideLine: MKPolyline {
        var kind: LegKind = .bike
        /// Die alte Linie — dünn, grau, gestrichelt.
        var faded = false
    }

    final class Pin: MKPointAnnotation {
        var tint: UIColor = .systemGreen
        var glyph: String = "mappin"
        var isRider = false
    }

    /// A junction with traffic lights. `fromPlan` says who owns it: the ones
    /// belonging to the drawn plan are cleared whenever the plan is redrawn,
    /// the ones handed over for a ride in progress outlive it.
    final class SignalDot: MKPointAnnotation {
        var fromPlan = true
    }

    /// A stretch of the recorded ride, in the colour of the speed it was
    /// ridden at. One polyline per run of equal colour: MapKit draws a
    /// polyline in exactly one colour, so a line that changes colour is
    /// several lines.
    final class TrackLine: MKPolyline {
        var step = 0
    }

    /// Where the ride stood still. Yellow at a lit junction, grey elsewhere —
    /// the difference the whole counting is about.
    final class StopDot: MKPointAnnotation {
        var atSignal = false
        var seconds: TimeInterval = 0
    }

    /// A red light on a ridden route reads at a glance: yellow, a light, and
    /// the seconds it cost. Everything else that stood still is grey and small
    /// — the difference between the two is what the counting is about.
    final class StopDotView: MKAnnotationView {
        private let icon = UIImageView()
        private let label = UILabel()

        override init(annotation: MKAnnotation?, reuseIdentifier: String?) {
            super.init(annotation: annotation, reuseIdentifier: reuseIdentifier)
            let stack = UIStackView(arrangedSubviews: [icon, label])
            stack.spacing = 2
            stack.alignment = .center
            stack.isLayoutMarginsRelativeArrangement = true
            stack.layoutMargins = UIEdgeInsets(top: 2, left: 4, bottom: 2, right: 5)
            stack.translatesAutoresizingMaskIntoConstraints = false
            addSubview(stack)
            NSLayoutConstraint.activate([
                stack.leadingAnchor.constraint(equalTo: leadingAnchor), stack.trailingAnchor.constraint(equalTo: trailingAnchor),
                stack.topAnchor.constraint(equalTo: topAnchor), stack.bottomAnchor.constraint(equalTo: bottomAnchor),
            ])
            icon.contentMode = .scaleAspectFit
            icon.preferredSymbolConfiguration = .init(pointSize: 9, weight: .bold)
            label.font = .monospacedDigitSystemFont(ofSize: 10, weight: .bold)
            layer.cornerRadius = 9
            layer.borderWidth = 1.5
            layer.borderColor = UIColor.white.cgColor
            collisionMode = .circle
            canShowCallout = false
        }

        required init?(coder: NSCoder) { fatalError() }

        func configure(_ dot: StopDot) {
            let seconds = Int(dot.seconds.rounded())
            if dot.atSignal {
                backgroundColor = UIColor(red: 0.98, green: 0.78, blue: 0.11, alpha: 1)
                icon.image = UIImage(systemName: "light.beacon.max.fill")
                icon.tintColor = .black.withAlphaComponent(0.75)
                label.textColor = .black
                displayPriority = .required
                zPriority = .defaultSelected
            } else {
                backgroundColor = .systemGray3
                icon.image = UIImage(systemName: "pause.fill")
                icon.tintColor = .white
                label.textColor = .white
                displayPriority = .defaultLow
                zPriority = .defaultUnselected
            }
            label.text = seconds < 60 ? "\(seconds)s" : "\(seconds / 60):\(String(format: "%02d", seconds % 60))"
            frame.size = systemLayoutSizeFitting(UIView.layoutFittingCompressedSize)
        }
    }

    /// Where the rider is, pointing the way they are going.
    final class Rider: MKPointAnnotation {
        var course: CLLocationDirection = -1
    }

    final class RiderView: MKAnnotationView {
        private let arrow = UIImageView()

        override init(annotation: MKAnnotation?, reuseIdentifier: String?) {
            super.init(annotation: annotation, reuseIdentifier: reuseIdentifier)
            frame = CGRect(x: 0, y: 0, width: 30, height: 30)
            backgroundColor = UIColor(red: 0.00, green: 0.62, blue: 0.51, alpha: 1)
            layer.cornerRadius = 15
            layer.borderWidth = 3
            layer.borderColor = UIColor.white.cgColor
            layer.shadowColor = UIColor.black.cgColor
            layer.shadowOpacity = 0.3
            layer.shadowRadius = 3
            layer.shadowOffset = .zero
            arrow.frame = bounds.insetBy(dx: 6, dy: 6)
            arrow.contentMode = .scaleAspectFit
            arrow.tintColor = .white
            arrow.image = UIImage(systemName: "location.north.fill")
            addSubview(arrow)
            displayPriority = .required
            zPriority = .max
            collisionMode = .circle
            canShowCallout = false
        }

        required init?(coder: NSCoder) { fatalError() }

        /// The arrow points where the ride is going — **on screen**, which is
        /// not the same as "at the course". While the map follows the rider it
        /// is itself turned to the course, and an arrow rotated by the course
        /// on top of that points at twice the angle. So it is always the
        /// course *minus the map's own heading*.
        ///
        /// Without any course at all the arrow would point north and lie about
        /// it; then a plain dot says the same thing without the lie.
        func configure(_ r: Rider, mapHeading: CLLocationDirection) {
            arrow.isHidden = r.course < 0
            arrow.transform = CGAffineTransform(rotationAngle: (r.course - mapHeading) * .pi / 180)
        }
    }

    final class SignalDotView: MKAnnotationView {
        override init(annotation: MKAnnotation?, reuseIdentifier: String?) {
            super.init(annotation: annotation, reuseIdentifier: reuseIdentifier)
            frame = CGRect(x: 0, y: 0, width: 9, height: 9)
            backgroundColor = UIColor(red: 0.98, green: 0.71, blue: 0.11, alpha: 1)
            layer.cornerRadius = 4.5
            layer.borderWidth = 1.5
            layer.borderColor = UIColor.white.cgColor
            displayPriority = .defaultLow
            collisionMode = .circle
            canShowCallout = false
        }

        required init?(coder: NSCoder) { fatalError() }
    }

    /// Duration and transfers of one option, placed on its route.
    final class OptionLabel: MKPointAnnotation {
        var optionID: TripOption.ID?
        var symbol = "bicycle"
        var text = ""
        var color: UIColor = .systemGray
        var selected = false
    }

    final class OptionLabelView: MKAnnotationView {
        private let icon = UIImageView()
        private let label = UILabel()

        override init(annotation: MKAnnotation?, reuseIdentifier: String?) {
            super.init(annotation: annotation, reuseIdentifier: reuseIdentifier)
            let stack = UIStackView(arrangedSubviews: [icon, label])
            stack.spacing = 4
            stack.alignment = .center
            stack.isLayoutMarginsRelativeArrangement = true
            stack.layoutMargins = UIEdgeInsets(top: 3, left: 6, bottom: 3, right: 7)
            stack.translatesAutoresizingMaskIntoConstraints = false
            addSubview(stack)
            NSLayoutConstraint.activate([
                stack.leadingAnchor.constraint(equalTo: leadingAnchor), stack.trailingAnchor.constraint(equalTo: trailingAnchor),
                stack.topAnchor.constraint(equalTo: topAnchor), stack.bottomAnchor.constraint(equalTo: bottomAnchor),
            ])
            label.font = .monospacedDigitSystemFont(ofSize: 12, weight: .semibold)
            icon.contentMode = .scaleAspectFit
            icon.preferredSymbolConfiguration = .init(pointSize: 11, weight: .semibold)
            layer.cornerRadius = 9
            layer.borderWidth = 1.5
            collisionMode = .rectangle
        }

        required init?(coder: NSCoder) { fatalError() }

        func configure(_ a: OptionLabel) {
            icon.image = UIImage(systemName: a.symbol)
            label.text = a.text
            let fg: UIColor = a.selected ? .white : .secondaryLabel
            icon.tintColor = fg
            label.textColor = fg
            backgroundColor = a.selected ? a.color : .systemBackground.withAlphaComponent(0.92)
            layer.borderColor = (a.selected ? a.color : UIColor.systemGray3).cgColor
            displayPriority = a.selected ? .required : .defaultHigh
            zPriority = a.selected ? .max : .defaultUnselected
            let size = systemLayoutSizeFitting(UIView.layoutFittingCompressedSize)
            frame.size = size
            centerOffset = .zero
        }
    }

}
