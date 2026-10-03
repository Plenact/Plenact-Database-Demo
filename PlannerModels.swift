// -------------------------------------------------------------------------------------------------
// @file       PlannerModels.swift
// @brief      Codable data model for the demo Planner snapshot
// @details    Represent an undated seven-day plan, life plan, and independent notes
//
// @notes      IDs identify editable items within one complete Planner snapshot
//             schemaVersion describes payload shape; it is not a content revision
//
// -------------------------------------------------------------------------------------------------
import Foundation

// -------------------------------------- MARK: - Planner Document ------------------------------ //

///
/// Complete Planner payload stored as one snapshot
///
struct PlannerDocument: Codable, Equatable {

    static let currentSchemaVersion = 1

    var schemaVersion: Int                     /* The schema version of the document    */    
    var weekPlan:      PlannerWeekPlan         /* The week plan section of the document */
    var lifePlan:      PlannerLifePlan         /* The life plan section of the document */ 
    var notes:         [PlannerNote]           /* The notes section of the document     */

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"  /* The schema version of the document    */
        case weekPlan     = "week_plan"        /* The week plan section of the document */
        case lifePlan      = "life_plan"       /* The life plan section of the document */
        case notes                             /* The notes section of the document     */
    }

    ///
    /// @brief      Create an empty Planner document with seven ordered day slots
    /// @return     (PlannerDocument) version-one empty snapshot
    ///
    static func empty() -> PlannerDocument {

        PlannerDocument(
            schemaVersion: currentSchemaVersion,
            weekPlan: PlannerWeekPlan(
                days: (0..<7).map { PlannerDay(dayIndex: $0) }
            ),
            lifePlan: PlannerLifePlan(),
            notes: []
        )
    }

    ///
    /// @brief      Explain why this document cannot be sent to the Planner API
    /// @return     (String?) validation feedback, or nil when the snapshot is valid
    ///
    var validationMessage: String? {

        guard schemaVersion == Self.currentSchemaVersion,
              weekPlan.days.count == 7,
              weekPlan.days.enumerated().allSatisfy({ $0.offset == $0.element.dayIndex }) else {

            return "Planner must contain seven ordered day slots."
        }

        var seenIDs = Set<Int>()

        func registerID(_ itemID: Int) -> Bool {

            itemID > 0 && seenIDs.insert(itemID).inserted
        }

        func hasText(_ value: String) -> Bool {

            !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }

        for day in weekPlan.days {

            for goal in day.goals {

                guard registerID(goal.id), hasText(goal.description) else {

                    return "Each goal needs a unique ID and description."
                }
            }

            for schedule in day.schedules {

                guard registerID(schedule.id) else {
                    
                    return "Each schedule needs a unique ID."
                }

                for event in schedule.events {

                    guard registerID(event.id),
                          (0...1439).contains(event.timeOfDayMinutes),
                          hasText(event.description) else {

                        return "Each event needs a unique ID, valid time, and description."
                    }
                }
            }

            for card in day.cards {

                guard registerID(card.id), hasText(card.title), hasText(card.name) else {

                    return "Each card needs a unique ID, title, and name."
                }
            }
        }

        for goal in lifePlan.goals {

            guard registerID(goal.id), hasText(goal.description) else {

                return "Each Life Plan goal needs a unique ID and description."
            }
        }

        for milestone in lifePlan.milestones {

            guard registerID(milestone.id),
                  hasText(milestone.description),
                  hasText(milestone.category) else {

                return "Each milestone needs a unique ID, description, and category."
            }
        }

        for note in notes where !registerID(note.id) {
            return "Each note needs a unique ID."
        }

        return nil
    }

    ///
    /// @brief      Find the next positive ID for a new nested item
    /// @return     (Int) one greater than every ID currently in the snapshot
    ///
    var nextItemID: Int {

        var itemIDs = notes.map(\.id)       /* Start with the IDs from the notes section */

        itemIDs.append(contentsOf: lifePlan.goals.map(\.id))
        itemIDs.append(contentsOf: lifePlan.milestones.map(\.id))

        for day in weekPlan.days {
            itemIDs.append(contentsOf: day.goals.map(\.id))
            itemIDs.append(contentsOf: day.schedules.map(\.id))
            itemIDs.append(contentsOf: day.cards.map(\.id))
            itemIDs.append(contentsOf: day.schedules.flatMap(\.events).map(\.id))
        }

        return (itemIDs.max() ?? 0) + 1
    }
}


// -------------------------------------- MARK: - Week Plan ------------------------------------- //

///
/// Seven ordered, undated day slots
///
struct PlannerWeekPlan: Codable, Equatable {

    var days: [PlannerDay]    /* The days within the week */
}

///
/// One generic day slot; dayIndex is stable from zero through six
///
struct PlannerDay: Codable, Equatable, Identifiable {

    var dayIndex:  Int                  /* The index of the day within the week */
    var goals:     [PlannerGoal]        /* The goals within the day             */
    var schedules: [PlannerSchedule]    /* The schedules within the day         */
    var cards:     [PlannerCard]        /* The cards within the day             */

    var id: Int {
        dayIndex        /* The index of the day within the week */
    }

    enum CodingKeys: String, CodingKey {
        case dayIndex = "day_index"    /* The index of the day within the week */
        case goals                     /* The goals within the day             */
        case schedules                 /* The schedules within the day         */
        case cards                     /* The cards within the day             */
    }

    ///
    /// @brief      Initialize a day with empty child collections by default
    /// @param[in]  dayIndex    Ordered slot from zero through six
    /// @return     (PlannerDay) configured day slot
    ///
    init(
        dayIndex:  Int,                     /* The index of the day within the week */
        goals:     [PlannerGoal]     = [],  /* The goals within the day             */
        schedules: [PlannerSchedule] = [],  /* The schedules within the day         */
        cards:     [PlannerCard]     = []   /* The cards within the day             */
    ) {
        self.dayIndex  = dayIndex
        self.goals     = goals
        self.schedules = schedules
        self.cards     = cards
    }
}

///
/// A goal belonging to one Day or to the Life Plan; these are independent entries
///
struct PlannerGoal: Codable, Equatable, Identifiable {

    var id:          Int        /* The unique identifier of the goal */
    var description: String     /* The description of the goal       */
    var priority:    Int        /* The priority of the goal          */
}

///
/// A schedule contains events positioned within its parent day
///
struct PlannerSchedule: Codable, Equatable, Identifiable {

    var id:     Int               /* The unique identifier of the schedule */
    var events: [PlannerEvent]    /* The events within the schedule        */
}

///
/// An event time is a minute offset from midnight, without a calendar date or timezone
///
struct PlannerEvent: Codable, Equatable, Identifiable {

    var id:               Int       /* The unique identifier of the event                    */
    var timeOfDayMinutes: Int       /* The time of day of the event in minutes from midnight */
    var description:      String    /* The description of the event                          */

    enum CodingKeys: String, CodingKey {
        case id
        case timeOfDayMinutes = "time_of_day_minutes"
        case description
    }
}

///
/// A small integer-valued card belonging to one Day
///
struct PlannerCard: Codable, Equatable, Identifiable {

    var id:    Int      /* The unique identifier of the card */
    var title: String   /* The title of the card             */
    var value: Int      /* The integer value of the card     */
    var name:  String   /* The name associated with the card */
}


// -------------------------------------- MARK: - Life Plan And Notes --------------------------- //

///
/// Long-term goals and milestones, independent of Week Plan goals
///
struct PlannerLifePlan: Codable, Equatable {

    var goals:      [PlannerGoal]      = []     /* Long-term goals for the Life Plan */
    var milestones: [PlannerMilestone] = []     /* Milestones for the Life Plan      */
}

///
/// A categorized milestone in the Life Plan
///
struct PlannerMilestone: Codable, Equatable, Identifiable {

    var id:          Int        /* The unique identifier of the milestone */
    var description: String     /* The description of the milestone       */
    var category:    String     /* The category of the milestone          */
    var notes:       String     /* Additional notes for the milestone     */
}

///
/// An independent Planner note
///
struct PlannerNote: Codable, Equatable, Identifiable {

    var id:   Int       /* The unique identifier of the note */
    var text: String    /* The content of the note           */
}


// -------------------------------------- MARK: - API Responses --------------------------------- //

///
/// Planner snapshot and server-maintained storage timestamps
///
struct PlannerLoadResponse: Decodable {

    let planner:   PlannerDocument?     /* The planner snapshot, if available                        */
    let createdAt: String?              /* Timestamp when the planner was created, if available      */
    let updatedAt: String?              /* Timestamp when the planner was last updated, if available */

    enum CodingKeys: String, CodingKey {
        case planner
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

///
/// Successful response from a Planner snapshot replacement
///
struct PlannerSaveResponse: Decodable {

    let saved:     Bool         /* Whether the save operation was successful   */
    let createdAt: String       /* Timestamp when the planner was created      */
    let updatedAt: String       /* Timestamp when the planner was last updated */

    enum CodingKeys: String, CodingKey {
        case saved
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}


// -------------------------------------- MARK: - Planner Sections ------------------------------ //

enum PlannerSection: String, CaseIterable, Identifiable {

    case weekPlan       /* Week Plan section */
    case lifePlan       /* Life Plan section */
    case notes          /* Notes section     */

    var id: String {
        rawValue        /* raw identifier of section */
    }

    var title: String {

        switch self {
            case .weekPlan:
                return "Week Plan"
            case .lifePlan:
                return "Life Plan"
            case .notes:
                return "Notes"
        }
    }
}