# Apple DTS request (draft)

Draft for Jimmy to complete and send through Apple Developer Technical
Support. Replace the bracketed parts with M1 results before sending.

## Summary

Our iOS app, Honoured, lets people sign daily step goals ("contracts") with
themselves. We need to tell the person, within about five minutes, that the
iPhone has counted the step goal, including while the iPhone is locked in a
pocket. Today the app learns of the goal 30 to 60 minutes late. We would like
Apple's guidance on a supported approach.

## Current implementation

- `HKObserverQuery` for `stepCount`, with
  `enableBackgroundDelivery(for:frequency: .immediate)` requested at launch.
- In each delivery: an `HKStatisticsQuery` for today's total, then a local
  notification if the goal is met.
- `BGAppRefreshTask` as a fallback (earliest begin date one hour).
- No Watch app. iOS 16 and later.

Measured on [device, iOS version], from our diagnostics log:

- [median and range of minutes between the estimated crossing and the
  observer delivery]
- [whether `queryPedometerData` returned data during a locked-device wake, or
  the error domain and code]
- [whether HealthKit statistics failed with `errorDatabaseInaccessible` while
  locked]

## Questions

1. Is there a supported way to have an iOS app woken while the device is
   locked when the pedometer step count crosses a threshold, without an Apple
   Watch app?
2. What delivery frequency can an app expect from
   `enableBackgroundDelivery(for: stepCount, frequency: .immediate)` on iOS, and
   is there a documented cap for step count?
3. During a HealthKit background delivery, `BGAppRefreshTask` or silent push
   launch while the device is locked, can the app call
   `CMPedometer.queryPedometerData`, and is that data protected until first
   unlock or until every unlock?
4. What approach does Apple recommend for notifying a user within about five
   minutes of reaching a daily step goal while the iPhone is locked?
5. Does `HKWorkoutSession` on iPhone (iOS 26) keep the app running in the
   background, and would App Review accept it for a user-started "walk to my
   goal" session?

## Minimal code

The smallest reproduction of what we do in a background delivery:

```swift
import CoreMotion
import HealthKit
import UserNotifications

final class StepGoalWatcher {
    private let store = HKHealthStore()
    private let pedometer = CMPedometer()
    private let goal: Double = 1_000

    /// Called from application(_:didFinishLaunchingWithOptions:).
    func start() {
        let type = HKQuantityType(.stepCount)
        let query = HKObserverQuery(sampleType: type, predicate: nil) { [weak self] _, completion, _ in
            self?.check { completion() }
        }
        store.execute(query)
        store.enableBackgroundDelivery(for: type, frequency: .immediate) { _, _ in }
    }

    private func check(done: @escaping () -> Void) {
        let start = Calendar.current.startOfDay(for: Date())
        // Question 3: does this return data while the device is locked?
        pedometer.queryPedometerData(from: start, to: Date()) { data, error in
            let steps = data?.numberOfSteps.doubleValue ?? 0
            NSLog("pedometer steps=%.0f error=%@", steps, String(describing: error))
            guard steps >= self.goal else { return done() }
            let content = UNMutableNotificationContent()
            content.title = "Goal reached"
            content.body = "\(Int(steps)) steps"
            let request = UNNotificationRequest(identifier: "goal", content: content, trigger: nil)
            UNUserNotificationCenter.current().add(request) { _ in done() }
        }
    }
}
```

## Attachments

- Exported motion probe log (`events.jsonl`) and session reports from M1.
- Screen recordings of a locked-device walk with timestamps.
