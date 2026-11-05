using System;

namespace os_sr_avqg
{
    // Flow-memory-only values used for the provider call, never persisted to the query row.
    public sealed class CalendarReferenceSnapshot
    {
        public CalendarReferenceSnapshot(Guid referenceId, int? activeState, string? email)
        {
            ReferenceId = referenceId;
            ActiveState = activeState;
            NormalizedEmail = (email ?? "").Trim().ToLowerInvariant();
        }

        public Guid ReferenceId { get; }
        public int? ActiveState { get; }
        public string NormalizedEmail { get; }
    }

    public static class ReferenceDriftPolicy
    {
        public static AvailabilityResult BeforeTerminalWrite(
            InterviewMode mode,
            CalendarReferenceSnapshot? originalTa,
            CalendarReferenceSnapshot? originalLocation,
            CalendarReferenceSnapshot? currentTa,
            CalendarReferenceSnapshot? currentLocation,
            AvailabilityResult proposedResult)
        {
            if ((mode != InterviewMode.Online && mode != InterviewMode.Onsite) ||
                !Unchanged(originalTa, currentTa) ||
                (mode == InterviewMode.Onsite && !Unchanged(originalLocation, currentLocation)))
                return AvailabilityResult.Failed("REFERENCE_CHANGED");
            return proposedResult;
        }

        private static bool Unchanged(CalendarReferenceSnapshot? original,
            CalendarReferenceSnapshot? current) =>
            original != null && current != null &&
            original.ReferenceId != Guid.Empty &&
            original.ReferenceId == current.ReferenceId &&
            original.ActiveState == 0 && current.ActiveState == original.ActiveState &&
            original.NormalizedEmail.Length > 0 &&
            string.Equals(original.NormalizedEmail, current.NormalizedEmail, StringComparison.Ordinal);
    }
}
