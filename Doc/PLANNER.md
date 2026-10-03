# Planner Data Contract

## Status And Purpose

This is the version-one data contract for the Planner feature in the Plenact Database Demo. The Swift model, editor UI, migration source, and PHP GET/PUT endpoint are implemented locally. Migration `004` has not been applied and `planner.php` has not been deployed, so hosted Planner persistence is not yet available.

The intended flow is:

```text
SwiftUI Planner tab <-> authenticated HTTPS API <-> MySQL-compatible storage
```

The demo's current shared app token and server-configured installation ID are development-only. Plenact production data must use an authenticated user or organization ownership model, as described in `PRODUCTION.md`.

## Confirmed Product Shape

- Planner has three conceptual sections: Week Plan, Life Plan, and Notes.
- A Week Plan contains exactly seven ordered, generic day slots. It is not tied to a calendar week, date range, locale, or timezone.
- Each Day has its own Goals, Schedules, and Cards.
- Day Goals are independent entries, not references to or copies linked to Life Plan Goals.
- Life Plan has Goals and Milestones.
- Notes are independent text records with integer IDs.
- Events use a time within their parent day, not a `Date` or timestamp.
- Repeatable goals, milestones, schedules, events, cards, and notes use positive integer IDs unique across one snapshot.
- Revision history is explicitly out of scope for the first Planner demo.

## Version-One Data Model

The Swift-style names below are proposed for clarity. JSON uses `snake_case`; Swift properties use `lowerCamelCase`. The original sketch's `descrip` is named `description` in the contract.

| Type | Fields | Meaning |
| --- | --- | --- |
| `PlannerDocument` | `schemaVersion: Int`, `weekPlan: WeekPlan`, `lifePlan: LifePlan`, `notes: [PlannerNote]` | One complete saved Planner snapshot. |
| `WeekPlan` | `days: [PlannerDay]` | Exactly seven day slots, ordered by `dayIndex`. |
| `PlannerDay` | `dayIndex: Int`, `goals: [Goal]`, `schedules: [Schedule]`, `cards: [Card]` | A generic slot in the seven-day plan; `dayIndex` is 0 through 6. |
| `Goal` | `id: Int`, `description: String`, `priority: Int` | A goal owned by the containing Day or Life Plan; the two collections are independent. |
| `LifePlan` | `goals: [Goal]`, `milestones: [Milestone]` | Long-term goals and milestones, separate from Day Goals. |
| `Milestone` | `id: Int`, `description: String`, `category: String`, `notes: String` | A categorized life-plan milestone. |
| `Schedule` | `id: Int`, `events: [Event]` | An ordered collection of events for its containing day. |
| `Event` | `id: Int`, `timeOfDayMinutes: Int`, `description: String` | An event at minute 0 through 1439 of its containing day. |
| `Card` | `id: Int`, `title: String`, `value: Int`, `name: String` | A small integer-valued item shown for a day. |
| `PlannerNote` | `id: Int`, `text: String` | An independent note. |

IDs are allocated client-side from the next integer not already present in the snapshot and validated as positive and unique across the document. `PlannerDay` uses its stable `dayIndex` (0 through 6) instead of a separate ID.

`timeOfDayMinutes` is an integer count from midnight: `0` is 00:00 and `1439` is 23:59. It avoids accidental date and timezone conversion for this undated week model. A future duration field, if needed, should be a separate positive integer number of minutes.

## Illustrative JSON Snapshot

This example shows the document envelope and one day shape. A valid stored Week Plan must contain all seven day slots, with `day_index` values 0 through 6.

```json
{
  "schema_version": 1,
  "week_plan": {
    "days": [
      {
        "day_index": 0,
        "goals": [
          {
            "id": 1,
            "description": "Take a walk",
            "priority": 1
          }
        ],
        "schedules": [
          {
            "id": 2,
            "events": [
              {
                "id": 3,
                "time_of_day_minutes": 540,
                "description": "Morning walk"
              }
            ]
          }
        ],
        "cards": [
          {
            "id": 4,
            "title": "Water",
            "value": 8,
            "name": "glasses"
          }
        ]
      },
      {
        "day_index": 1,
        "goals": [],
        "schedules": [],
        "cards": []
      },
      {
        "day_index": 2,
        "goals": [],
        "schedules": [],
        "cards": []
      },
      {
        "day_index": 3,
        "goals": [],
        "schedules": [],
        "cards": []
      },
      {
        "day_index": 4,
        "goals": [],
        "schedules": [],
        "cards": []
      },
      {
        "day_index": 5,
        "goals": [],
        "schedules": [],
        "cards": []
      },
      {
        "day_index": 6,
        "goals": [],
        "schedules": [],
        "cards": []
      }
    ]
  },
  "life_plan": {
    "goals": [],
    "milestones": []
  },
  "notes": []
}
```

This is a shape example. The sample values are not seeded automatically.

## Implemented Validation Rules

- Require `schema_version` to be a supported positive integer.
- Require exactly seven `week_plan.days`; each `day_index` occurs once and is in the range 0 through 6.
- Require arrays for goals, schedules, events, cards, milestones, and notes, including when empty.
- Require event `time_of_day_minutes` to be an integer from 0 through 1439.
- Require every repeated item ID to be a unique positive integer across the snapshot.
- Require `priority` and `value` to be JSON integers; their product meanings and ranges remain open.
- Require nonempty goal, milestone, event, card-title, card-name, and milestone-category text. Milestone notes and Planner note text may be empty strings.
- Require a valid event minute from 0 through 1439. There are no per-field text-length limits in v1; the API bounds the complete request body to 64 KiB.
- Accept milestone category as plain text for v1; a controlled category list is a future product decision.
- Validate the full document on both client and server. Client validation is for usability, not an authorization or data-integrity boundary.

The current Lifestyle values (Gender, Favorite Food, #Cats, Excited) are a separate preference record. They do not become part of `PlannerDocument` unless a later product decision explicitly joins them.

## Demo Persistence

The local migration `server/SQL/004_installation_planner.sql` creates one `installation_planner` row per configured demo installation:

| Column concept | Purpose |
| --- | --- |
| `installation_id` | ASCII/binary primary key for this demo's configured installation scope only. Not a Plenact production ownership model. |
| `planner_document` | MySQL JSON snapshot containing `schema_version`, Week Plan, Life Plan, and Notes. |
| `created_at`, `updated_at` | Server-generated UTC timestamps. |

The migration has not been applied. The local `planner.php` uses whole-document replacement and has no revision history. Concurrent writes are therefore last-write-wins; avoid simultaneous edits from multiple clients during this stage. The shared installation ID means the Simulator and physical iPhone access the same snapshot.

`created_at` and `updated_at` are server-generated UTC metadata. The demo does not claim a human storage author because its shared app token is not user identity. In Plenact, `created_by`/`updated_by` must come from the authenticated server-side principal. A future production revision number should only be added with an explicit concurrency, history, and retention design; `schema_version` is not that revision number.

## Local API Contract

`Server/api-dev/planner.php` implements these routes locally; it is not deployed yet:

| Method and route | Purpose | Proposed result |
| --- | --- | --- |
| `GET /api-dev/planner.php` | Load the configured installation's Planner snapshot. | HTTP 200 with `planner: null` and null timestamps if none exists; otherwise document and timestamps. |
| `PUT /api-dev/planner.php` | Validate and replace the entire Planner snapshot. | HTTP 200 with `saved`, `created_at`, and `updated_at`. |

Both routes require the app token and derive `installation_id` from private server configuration, never from the submitted Planner document. The endpoint authenticates before opening a database connection, uses prepared statements, requires JSON for PUT, limits the body to 64 KiB, validates the complete document, sets `Cache-Control: no-store`, and returns generic errors. The mobile shared-token design remains demo-only; keep production user/organization authorization separate.

## Remaining Product Decisions

- What does `Goal.priority` mean, and what range or ordering should it use?
- What do `Card.value` and `Card.name` represent, including units and valid ranges?
- What per-field text limits and collection-size limits should Plenact use beyond the 64 KiB demo request bound?
- Is whole-document last-write-wins acceptable for the single-user demo, and when will conflict detection or revision history become necessary?
- Which authenticated person or organization owns a Planner document in production, and what can a separate reader client see?

Apply the local migration once through the schema-administration workflow, deploy `planner.php`, then test a complete snapshot save and reload. Do not rerun migration `004`. Keep revision history out of the demo until its semantics are agreed.