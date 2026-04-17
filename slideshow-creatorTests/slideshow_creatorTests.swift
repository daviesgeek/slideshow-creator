//
//  slideshow_creatorTests.swift
//  slideshow-creatorTests
//
//  Created by Matthew Davies on 4/14/26.
//

import Foundation
import Testing
@testable import slideshow_creator

struct slideshow_creatorTests {

    @Test func transitionPlanDefaultsToHardCuts() throws {
        let items = [
            PhotoItem(url: URL(fileURLWithPath: "/tmp/a.jpg")),
            PhotoItem(url: URL(fileURLWithPath: "/tmp/b.jpg"))
        ]

        let plan = try FFmpegEncoder.makeTransitionPlan(
            items: items,
            secondsPerImage: 3,
            defaultTransitionToNext: .none,
            defaultTransitionDurationToNext: 1,
            fps: 30
        )

        #expect(plan.internalTransitions.count == 1)
        #expect(plan.internalTransitions[0].style == .none)
        #expect(plan.inputDurations == [3, 3])
        #expect(plan.terminalTransition == nil)
        #expect(plan.totalDuration == 6)
    }

    @Test func transitionPlanSupportsMixedAndTerminalTransitions() throws {
        let items = [
            PhotoItem(
                url: URL(fileURLWithPath: "/tmp/a.jpg"),
                isTransitionOverrideEnabled: true,
                transitionToNext: .fade,
                transitionDurationToNext: 1.0
            ),
            PhotoItem(
                url: URL(fileURLWithPath: "/tmp/b.jpg"),
                transitionToNext: PhotoTransitionStyle.none
            ),
            PhotoItem(
                url: URL(fileURLWithPath: "/tmp/c.jpg"),
                isTransitionOverrideEnabled: true,
                transitionToNext: .wipeleft,
                transitionDurationToNext: 0.5
            )
        ]

        let plan = try FFmpegEncoder.makeTransitionPlan(
            items: items,
            secondsPerImage: 3,
            defaultTransitionToNext: .none,
            defaultTransitionDurationToNext: 1,
            fps: 30
        )

        #expect(plan.internalTransitions.count == 2)
        #expect(plan.internalTransitions[0].style == .fade)
        #expect(plan.internalTransitions[1].style == .none)
        #expect(plan.inputDurations == [4, 3, 3])
        #expect(plan.terminalTransition?.style == .wipeleft)
        #expect(plan.terminalTransition?.duration == 0.5)
        #expect(plan.totalDuration == 9)
    }

    @Test func transitionPlanClampsTooLongDuration() throws {
        let items = [
            PhotoItem(
                url: URL(fileURLWithPath: "/tmp/a.jpg"),
                isTransitionOverrideEnabled: true,
                transitionToNext: .fade,
                transitionDurationToNext: 3
            ),
            PhotoItem(url: URL(fileURLWithPath: "/tmp/b.jpg"))
        ]

        let plan = try FFmpegEncoder.makeTransitionPlan(
            items: items,
            secondsPerImage: 3,
            defaultTransitionToNext: .none,
            defaultTransitionDurationToNext: 1,
            fps: 30
        )

        #expect(plan.internalTransitions[0].duration < 3)
        #expect(plan.inputDurations[0] < 6)
    }

    @Test func transitionPlanUsesPerPhotoDurationOverrides() throws {
        let items = [
            PhotoItem(
                url: URL(fileURLWithPath: "/tmp/a.jpg"),
                isSecondsOverrideEnabled: true,
                secondsOverride: 2.0,
                isTransitionOverrideEnabled: true,
                transitionToNext: .fade,
                transitionDurationToNext: 0.75
            ),
            PhotoItem(
                url: URL(fileURLWithPath: "/tmp/b.jpg"),
                isSecondsOverrideEnabled: true,
                secondsOverride: 4.0,
                transitionToNext: PhotoTransitionStyle.none
            ),
            PhotoItem(
                url: URL(fileURLWithPath: "/tmp/c.jpg"),
                isSecondsOverrideEnabled: true,
                secondsOverride: 1.5,
                isTransitionOverrideEnabled: true,
                transitionToNext: .fade,
                transitionDurationToNext: 0.5
            )
        ]

        let plan = try FFmpegEncoder.makeTransitionPlan(
            items: items,
            secondsPerImage: 3,
            defaultTransitionToNext: .none,
            defaultTransitionDurationToNext: 1,
            fps: 30
        )

        #expect(plan.contentDurations == [2.0, 4.0, 1.5])
        #expect(plan.inputDurations[0] > 2.0)
        #expect(plan.totalDuration == 7.5)
    }

}
