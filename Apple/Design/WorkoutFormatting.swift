import Foundation

extension TimeInterval {
  var workoutDuration: String {
    let minutes = Int(max(0, self)) / 60
    return minutes >= 60 ? "\(minutes / 60) ч \(minutes % 60) мин" : "\(minutes) мин"
  }
}
