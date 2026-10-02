# Architecture

Three parts: a native iOS app (with Watch app and widgets), a static **Program Builder**, and a static **Coach Portal**.

```mermaid
flowchart LR
    subgraph iOS["iPhone app — WorkoutApp/ (SwiftUI, SwiftData)"]
        App[App/<br/>RootTabView]
        Feat["Features/<br/>Home · Workout · Session · Program<br/>Measurements · Running · Info · Settings"]
        Ana[Analytics/<br/>1RM · volume · cycle stats]
        Svc["Services/<br/>RestTimer · HealthKit · ProgressionHints<br/>PRTracker · StressCalculator · Backup"]
        Models[(Models/<br/>SwiftData store)]
        App --> Feat
        Feat --> Ana
        Feat --> Svc
        Feat --> Models
        Ana --> Models
        Svc --> Models
    end

    Watch["VIGOR Watch App<br/>WatchSession"]
    Widgets["WorkoutWidgets<br/>Live Activity · StandBy"]
    HK[(HealthKit)]
    Builder["program-builder/<br/>static site (Vercel)"]
    Portal["portal/<br/>Coach Portal (static JS)"]

    Svc <-->|WatchSessionSync| Watch
    Svc -->|WidgetSnapshotSync| Widgets
    Svc <--> HK
    Builder -->|program template JSON| Svc
    Svc -->|WorkoutBackup export| Portal
```

| Path | Purpose |
|---|---|
| `WorkoutApp/` | iOS client (iOS 17+) |
| `VIGOR Watch App Watch App/` | watchOS companion |
| `WorkoutWidgets/` | Widgets and rest-timer Live Activity |
| `program-builder/` | Desktop program authoring (contract-tested against the app's template format) |
| `portal/` | Import an app export and explore it on a laptop |
