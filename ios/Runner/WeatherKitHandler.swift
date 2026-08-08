import Foundation
import WeatherKit
import CoreLocation
import Flutter

final class WeatherKitHandler: NSObject {
  func handle(call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard call.method == "getWeather" else {
      result(FlutterMethodNotImplemented)
      return
    }

    if #available(iOS 16.0, *) {
      getWeather(call: call, result: result)
    } else {
      result(FlutterError(
        code: "weather_kit_not_supported",
        message: "WeatherKit requires iOS 16.0 or higher.",
        details: nil
      ))
    }
  }

  @available(iOS 16.0, *)
  private func getWeather(call: FlutterMethodCall, result: @escaping FlutterResult) {
    let args = call.arguments as? [String: Any] ?? [:]
    guard let lat = args["latitude"] as? Double,
          let lng = args["longitude"] as? Double else {
      result(FlutterError(
        code: "invalid_args",
        message: "Parameters 'latitude' and 'longitude' are required.",
        details: nil
      ))
      return
    }

    let location = CLLocation(latitude: lat, longitude: lng)
    let service = WeatherService.shared

    Task {
      do {
        let weather = try await service.weather(for: location)
        var response = [String: Any]()

        // 1. Current Weather
        let current = weather.currentWeather
        response["current"] = [
          "condition": current.condition.description,
          "temperature_c": (current.temperature.converted(to: .celsius).value * 10).rounded() / 10,
          "apparent_temperature_c": (current.apparentTemperature.converted(to: .celsius).value * 10).rounded() / 10,
          "humidity": (current.humidity * 100).rounded() / 100,
          "wind_speed_kmh": (current.wind.speed.converted(to: .kilometersPerHour).value * 10).rounded() / 10,
          "wind_direction": current.wind.compassDirection.description,
          "pressure_hpa": (current.pressure.converted(to: .hectopascals).value * 10).rounded() / 10,
          "pressure_trend": current.pressureTrend.description,
          "uv_index": current.uvIndex.value,
          "visibility_km": (current.visibility.converted(to: .kilometers).value * 10).rounded() / 10,
          "dew_point_c": (current.dewPoint.converted(to: .celsius).value * 10).rounded() / 10,
          "cloud_cover": (current.cloudCover * 100).rounded() / 100,
          "is_daylight": current.isDaylight,
          "location": ["latitude": lat, "longitude": lng]
        ] as [String: Any]

        // 2. Hourly Forecast (up to 48 hours)
        let hourlyForecasts = weather.hourlyForecast.forecast
        var hourly = [[String: Any]]()
        let hourFormatter = DateFormatter()
        hourFormatter.dateFormat = "HH:mm"
        hourFormatter.timeZone = TimeZone.current
        let isoFormatter = ISO8601DateFormatter()

        for forecast in hourlyForecasts.prefix(48) {
          hourly.append([
            "hour": hourFormatter.string(from: forecast.date),
            "date": isoFormatter.string(from: forecast.date),
            "condition": forecast.condition.description,
            "temp_c": (forecast.temperature.converted(to: .celsius).value * 10).rounded() / 10,
            "apparent_temp_c": (forecast.apparentTemperature.converted(to: .celsius).value * 10).rounded() / 10,
            "humidity": (forecast.humidity * 100).rounded() / 100,
            "precip_chance": (forecast.precipitationChance * 100).rounded() / 100,
            "wind_speed_kmh": (forecast.wind.speed.converted(to: .kilometersPerHour).value * 10).rounded() / 10,
            "uv_index": forecast.uvIndex.value,
            "cloud_cover": (forecast.cloudCover * 100).rounded() / 100,
            "is_daylight": forecast.isDaylight
          ])
        }
        response["hourly"] = hourly

        // 3. Daily Forecast (up to 10 days)
        let dailyForecasts = weather.dailyForecast.forecast
        var daily = [[String: Any]]()
        let dayFormatter = DateFormatter()
        dayFormatter.dateFormat = "yyyy-MM-dd"
        let timeFormatter = DateFormatter()
        timeFormatter.dateFormat = "HH:mm"
        timeFormatter.timeZone = TimeZone.current

        for forecast in dailyForecasts.prefix(10) {
          var entry: [String: Any] = [
            "date": dayFormatter.string(from: forecast.date),
            "condition": forecast.condition.description,
            "high_c": (forecast.highTemperature.converted(to: .celsius).value * 10).rounded() / 10,
            "low_c": (forecast.lowTemperature.converted(to: .celsius).value * 10).rounded() / 10,
            "precip_chance": (forecast.precipitationChance * 100).rounded() / 100,
            "wind_speed_kmh": (forecast.wind.speed.converted(to: .kilometersPerHour).value * 10).rounded() / 10,
            "uv_index": forecast.uvIndex.value
          ]
          if let sunrise = forecast.sun.sunrise {
            entry["sunrise"] = timeFormatter.string(from: sunrise)
          }
          if let sunset = forecast.sun.sunset {
            entry["sunset"] = timeFormatter.string(from: sunset)
          }
          daily.append(entry)
        }
        response["daily"] = daily

        // 4. Weather Alerts
        var alertList = [[String: Any]]()
        if let alerts = weather.weatherAlerts {
          for alert in alerts {
            alertList.append([
              "summary": alert.summary,
              "severity": alert.severity.description,
              "source": alert.source,
              "region": alert.region ?? ""
            ])
          }
        }
        response["alerts"] = alertList

        DispatchQueue.main.async {
          result(response)
        }
      } catch {
        DispatchQueue.main.async {
          result(FlutterError(
            code: "weather_fetch_failed",
            message: error.localizedDescription,
            details: nil
          ))
        }
      }
    }
  }
}
