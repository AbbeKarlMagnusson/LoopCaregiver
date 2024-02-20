//
//  TimelineProvider.swift
//  LoopCaregiverWatchAppExtension
//
//  Created by Bill Gestrich on 12/18/23.
//

import Foundation
import LoopCaregiverKit
import LoopKit
import SwiftUI
import WidgetKit

class TimelineProvider: AppIntentTimelineProvider {
    
    @available(*, renamed: "getEntry()")
    func getEntry(composer: ServiceComposer, configuration: ConfigurationAppIntent, completion: @escaping (SimpleEntry) -> Void ) {
        Task {
            let result = await getEntry(composer: composer, configuration: configuration)
            completion(result)
        }
    }
    
    func getEntry(composer: ServiceComposer, configuration: ConfigurationAppIntent) async -> SimpleEntry {
        return await withCheckedContinuation { continuation in
            Task {
                
                var looper: Looper
                if let configurationLooper = try composer.accountServiceManager.getLoopers().first(where: {$0.id == configuration.looperID}) {
                    looper = configurationLooper
//                } else if let selectedLooper = composer.accountServiceManager.selectedLooper {
//                    looper = selectedLooper
                } else {
                    continuation.resume(returning: SimpleEntry(looper: nil, currentGlucoseSample: nil, lastGlucoseChange: nil, date: Date(), entryIndex: 0, isLastEntry: true, glucoseDisplayUnits: composer.settings.glucoseDisplayUnits))
                    return
                }
                
                let nightscoutDataSource = NightscoutDataSource(looper: looper, settings: composer.settings)
                let sortedSamples = try await nightscoutDataSource.fetchGlucoseSamples().sorted(by: {$0.date < $1.date})
                let latestGlucoseSample = sortedSamples.last
                let glucoseChange = getLastGlucoseChange(composer: composer, samples: sortedSamples)
                
                continuation.resume(returning: SimpleEntry(looper: looper, currentGlucoseSample: latestGlucoseSample, lastGlucoseChange: glucoseChange, date: Date(), entryIndex: 0, isLastEntry: true, glucoseDisplayUnits: composer.settings.glucoseDisplayUnits))
            }
        }
    }
    
    func getLastGlucoseChange(composer: ServiceComposer, samples: [NewGlucoseSample]) -> Double? {
        guard samples.count > 1 else {
            return nil
        }
        let lastGlucoseValue = samples[samples.count - 1].presentableUserValue(displayUnits: composer.settings.glucoseDisplayUnits)
        let priorGlucoseValue = samples[samples.count - 2].presentableUserValue(displayUnits: composer.settings.glucoseDisplayUnits)
        return lastGlucoseValue - priorGlucoseValue
    }
    
    func placeholder(in context: Context) -> SimpleEntry {
        let composer = ServiceComposerProduction()
        let sample = NewGlucoseSample(date: Date(), quantity: .init(unit: .milligramsPerDeciliter, doubleValue: 100), condition: .none, trend: .up, trendRate: .none, isDisplayOnly: false, wasUserEntered: false, syncIdentifier: "1345")
        return SimpleEntry(looper: nil, currentGlucoseSample: sample, lastGlucoseChange: nil, date: Date(), entryIndex: 0, isLastEntry: true, glucoseDisplayUnits: composer.settings.glucoseDisplayUnits)
    }

    func snapshot(for configuration: ConfigurationAppIntent, in context: Context) async -> SimpleEntry {
        return await getEntry(composer: ServiceComposerProduction(), configuration: configuration)
    }
    
    func timeline(for configuration: ConfigurationAppIntent, in context: Context) async -> Timeline<SimpleEntry> {
        let composer = ServiceComposerProduction()
        let entry = await getEntry(composer: composer, configuration: configuration)
        
        var entries = [SimpleEntry]()
        let nowDate = Date()
        
        var nextRequestDate: Date = nowDate.addingTimeInterval(60*5) //Default interval
        if let nextExpectedGlucoseDate = entry.nextExpectedGlucoseDate(), nextExpectedGlucoseDate > nowDate {
            nextRequestDate = nextExpectedGlucoseDate.addingTimeInterval(60*1) //Extra minute to allow time for upload.
        }
        
        let looper = composer.accountServiceManager.loopers.first(where: {$0.id == configuration.looperID})
        
        let indexCount = 60
        for index in 0..<indexCount {
            let isLastEntry = index == (indexCount - 1)
            let futureEntry = SimpleEntry(looper: looper, currentGlucoseSample: entry.currentGlucoseSample,
                                          lastGlucoseChange: entry.lastGlucoseChange,
                                          date: nowDate.addingTimeInterval(60 * TimeInterval(index)),
                                          entryIndex: index,
                                          isLastEntry: isLastEntry,
                                          glucoseDisplayUnits: composer.settings.glucoseDisplayUnits)
            entries.append(futureEntry)
        }
        return Timeline(entries: entries, policy: .after(nextRequestDate))
    }
    
    func recommendations() -> [AppIntentRecommendation<ConfigurationAppIntent>] {
        /*
         
         The soution:
         
         1. No recommended widget shows until Caregiver app is opened
         2. All available Loopers show.
         3. If Looper is deleted, a lookup by name can be done.
            Make a unique name constraint in Core Data?
         4. If Looper can't be found by name, show an error that widget needs reconfigured.
            This could be a safety mechanism. Parents may have multilpe children and be looking at the wrong looper.
         
         
         Ask watch for Loopers
         
         -Watch on appear, send message to phone asking for loopers
         -Show message to open phone
         -Phone home view
            Monitor for WatchManager message
            Send Loopers
         
         Smoke Test
         
         -Delete both sims
         -Close both sims
         -Build to both sims
         -Check that widget unavaiable
         -Open Phone and add 2 Loopers
         -Open watch and add Loopers
         -Check that 2 widgets can be added
         -Check that tapping widget opens respective Looper
         -Delete 1 Looper on Watch
         -Check that error shows
         */
        var result: [AppIntentRecommendation<ConfigurationAppIntent>] = []
        let composer = ServiceComposerProduction()
        do {
            let availableLoopers = try composer.accountServiceManager.getLoopers()
            result = availableLoopers.compactMap({ looper in
                let appIntent = ConfigurationAppIntent(looperID: looper.id, name: looper.name)
                guard let name = appIntent.name else {return nil}
                return AppIntentRecommendation(intent: appIntent, description: name)
            })
        } catch {
            print(error)
        }
        
//        if result.isEmpty {
//            let placeholderRecommendation = AppIntentRecommendation(intent: ConfigurationAppIntent(looperID: nil, name: nil), description: "TODO: Default!")
//            result = [placeholderRecommendation]
//        }
        
        return result
    }
}
