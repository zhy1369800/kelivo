import Foundation
import MapKit
import CoreLocation
import Flutter

final class MapKitHandler: NSObject {
  func handle(call: FlutterMethodCall, result: @escaping FlutterResult) {
    let args = call.arguments as? [String: Any] ?? [:]
    switch call.method {
    case "searchPlaces":
      searchPlaces(args: args, result: result)
    case "getRoute":
      getRoute(args: args, result: result)
    case "getEta":
      getEta(args: args, result: result)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  // MARK: - Search Places (MKLocalSearch)

  private func searchPlaces(args: [String: Any], result: @escaping FlutterResult) {
    guard let query = args["query"] as? String, !query.isEmpty else {
      result(FlutterError(code: "invalid_args", message: "Parameter 'query' is required.", details: nil))
      return
    }
    let lat = args["latitude"] as? Double
    let lon = args["longitude"] as? Double
    let radius = (args["radius_meters"] as? Double) ?? 1000.0
    let limit = (args["limit"] as? Int) ?? 10

    DispatchQueue.main.async {
      let request = MKLocalSearch.Request()
      request.naturalLanguageQuery = query
      if let lat = lat, let lon = lon {
        let center = CLLocationCoordinate2D(latitude: lat, longitude: lon)
        request.region = MKCoordinateRegion(
          center: center,
          latitudinalMeters: radius * 2,
          longitudinalMeters: radius * 2
        )
      }
      MKLocalSearch(request: request).start { response, error in
        if let error = error {
          result(FlutterError(code: "search_failed", message: error.localizedDescription, details: nil))
          return
        }
        let items = response?.mapItems ?? []
        let userLocation: CLLocation? = (lat != nil && lon != nil)
          ? CLLocation(latitude: lat!, longitude: lon!) : nil
        let results: [[String: Any?]] = Array(items.prefix(limit)).map { item in
          let coord = item.placemark.coordinate
          let distance = userLocation?.distance(from: CLLocation(latitude: coord.latitude, longitude: coord.longitude))
          let addressParts = [
            item.placemark.subThoroughfare,
            item.placemark.thoroughfare,
            item.placemark.locality,
            item.placemark.administrativeArea,
            item.placemark.country,
          ].compactMap { $0 }
          return [
            "name": item.name,
            "phone": item.phoneNumber,
            "url": item.url?.absoluteString,
            "latitude": coord.latitude,
            "longitude": coord.longitude,
            "address": addressParts.joined(separator: " "),
            "distance_m": distance.map { Int($0) },
          ]
        }
        result(["results": results, "count": results.count, "query": query])
      }
    }
  }

  // MARK: - Resolve location string/coord → MKMapItem

  private func resolveMapItem(
    address: String?,
    latitude: Double?,
    longitude: Double?,
    completion: @escaping (MKMapItem?, String?) -> Void
  ) {
    if let lat = latitude, let lon = longitude {
      let coord = CLLocationCoordinate2D(latitude: lat, longitude: lon)
      completion(MKMapItem(placemark: MKPlacemark(coordinate: coord)), nil)
    } else if let address = address, !address.isEmpty {
      CLGeocoder().geocodeAddressString(address) { placemarks, error in
        guard let first = placemarks?.first else {
          completion(nil, error?.localizedDescription ?? "Address not found: \(address)")
          return
        }
        completion(MKMapItem(placemark: MKPlacemark(placemark: first)), nil)
      }
    } else {
      completion(nil, "Provide either an address or latitude+longitude.")
    }
  }

  // MARK: - Get Route (MKDirections full)

  private func getRoute(args: [String: Any], result: @escaping FlutterResult) {
    let mode = transportType(from: args["mode"] as? String)
    resolveMapItem(
      address: args["from_address"] as? String,
      latitude: args["from_latitude"] as? Double,
      longitude: args["from_longitude"] as? Double
    ) { [weak self] fromItem, fromErr in
      guard let fromItem = fromItem else {
        result(FlutterError(code: "invalid_args", message: "Cannot resolve 'from': \(fromErr ?? "")", details: nil))
        return
      }
      self?.resolveMapItem(
        address: args["to_address"] as? String,
        latitude: args["to_latitude"] as? Double,
        longitude: args["to_longitude"] as? Double
      ) { toItem, toErr in
        guard let toItem = toItem else {
          result(FlutterError(code: "invalid_args", message: "Cannot resolve 'to': \(toErr ?? "")", details: nil))
          return
        }
        DispatchQueue.main.async {
          let req = MKDirections.Request()
          req.source = fromItem
          req.destination = toItem
          req.transportType = mode
          req.requestsAlternateRoutes = false
          MKDirections(request: req).calculate { response, error in
            if let error = error {
              result(FlutterError(code: "route_failed", message: error.localizedDescription, details: nil))
              return
            }
            guard let route = response?.routes.first else {
              result(FlutterError(code: "no_route", message: "No route found between the specified locations.", details: nil))
              return
            }
            let steps: [[String: Any]] = route.steps
              .filter { !$0.instructions.isEmpty }
              .map { ["instruction": $0.instructions, "distance_m": Int($0.distance)] }
            result([
              "distance_km": (route.distance / 1000.0 * 100).rounded() / 100,
              "duration_minutes": (route.expectedTravelTime / 60.0 * 10).rounded() / 10,
              "polyline_point_count": route.polyline.pointCount,
              "steps": steps,
            ])
          }
        }
      }
    }
  }

  // MARK: - Get ETA (MKDirections lightweight)

  private func getEta(args: [String: Any], result: @escaping FlutterResult) {
    let mode = transportType(from: args["mode"] as? String)
    resolveMapItem(
      address: args["from_address"] as? String,
      latitude: args["from_latitude"] as? Double,
      longitude: args["from_longitude"] as? Double
    ) { [weak self] fromItem, fromErr in
      guard let fromItem = fromItem else {
        result(FlutterError(code: "invalid_args", message: "Cannot resolve 'from': \(fromErr ?? "")", details: nil))
        return
      }
      self?.resolveMapItem(
        address: args["to_address"] as? String,
        latitude: args["to_latitude"] as? Double,
        longitude: args["to_longitude"] as? Double
      ) { toItem, toErr in
        guard let toItem = toItem else {
          result(FlutterError(code: "invalid_args", message: "Cannot resolve 'to': \(toErr ?? "")", details: nil))
          return
        }
        DispatchQueue.main.async {
          let req = MKDirections.Request()
          req.source = fromItem
          req.destination = toItem
          req.transportType = mode
          MKDirections(request: req).calculateETA { response, error in
            if let error = error {
              result(FlutterError(code: "eta_failed", message: error.localizedDescription, details: nil))
              return
            }
            guard let eta = response else {
              result(FlutterError(code: "no_eta", message: "ETA not available.", details: nil))
              return
            }
            let formatter = ISO8601DateFormatter()
            result([
              "distance_km": (eta.distance / 1000.0 * 100).rounded() / 100,
              "duration_minutes": (eta.expectedTravelTime / 60.0 * 10).rounded() / 10,
              "expected_arrival": formatter.string(from: eta.expectedArrivalDate),
            ])
          }
        }
      }
    }
  }

  // MARK: - Helpers

  private func transportType(from mode: String?) -> MKDirectionsTransportType {
    switch mode?.lowercased() {
    case "walking": return .walking
    case "transit": return .transit
    default: return .automobile
    }
  }
}
