import React, { useCallback, useEffect, useRef, useState } from "react";
import { toast } from "react-toastify";

import {
  listSubmissions,
  getSubmissionStatus,
  Submission,
  SubmissionStatus,
} from "../services/api";

// ---------------------------------------------------------------------------
// Status badge helper
// ---------------------------------------------------------------------------

const STATUS_CONFIG: Record<
  SubmissionStatus,
  { label: string; bg: string; text: string; dot: string }
> = {
  uploaded: {
    label: "Uploaded",
    bg: "bg-yellow-100",
    text: "text-yellow-800",
    dot: "bg-yellow-400",
  },
  processing: {
    label: "Processing",
    bg: "bg-blue-100",
    text: "text-blue-800",
    dot: "bg-blue-400",
  },
  complete: {
    label: "Complete",
    bg: "bg-green-100",
    text: "text-green-800",
    dot: "bg-green-500",
  },
  failed: {
    label: "Failed",
    bg: "bg-red-100",
    text: "text-red-800",
    dot: "bg-red-500",
  },
};

const StatusBadge: React.FC<{ status: SubmissionStatus }> = ({ status }) => {
  const cfg = STATUS_CONFIG[status] ?? STATUS_CONFIG.uploaded;

  return (
    <span
      className={`inline-flex items-center gap-1.5 px-2.5 py-0.5 rounded-full text-xs font-medium ${cfg.bg} ${cfg.text}`}
    >
      <span className={`w-1.5 h-1.5 rounded-full ${cfg.dot}`} />
      {cfg.label}
    </span>
  );
};

// ---------------------------------------------------------------------------
// Helper: is the status "final" (no more polling needed)?
// ---------------------------------------------------------------------------

function isFinalStatus(status: SubmissionStatus): boolean {
  return status === "complete" || status === "failed";
}

// ---------------------------------------------------------------------------
// Component
// ---------------------------------------------------------------------------

const POLL_INTERVAL_MS = 10_000; // 10 seconds

const SubmissionList: React.FC = () => {
  const [submissions, setSubmissions] = useState<Submission[]>([]);
  const [loading, setLoading] = useState(true);
  const pollRef = useRef<ReturnType<typeof setInterval> | null>(null);

  // -----------------------------------------------------------------------
  // Fetch all submissions
  // -----------------------------------------------------------------------

  const fetchSubmissions = useCallback(async () => {
    try {
      const data = await listSubmissions();
      setSubmissions(data);
    } catch {
      toast.error("Failed to load submissions.");
    } finally {
      setLoading(false);
    }
  }, []);

  // -----------------------------------------------------------------------
  // Poll non-final submissions for status updates
  // -----------------------------------------------------------------------

  const pollStatuses = useCallback(async () => {
    const pending = submissions.filter((s) => !isFinalStatus(s.status));
    if (pending.length === 0) return;

    const updates = await Promise.allSettled(
      pending.map((s) =>
        getSubmissionStatus(s.id).then((res) => ({
          id: s.id,
          status: res.status,
        }))
      )
    );

    setSubmissions((prev) => {
      let changed = false;
      const next = prev.map((s) => {
        const fulfilled = updates.find(
          (u) =>
            u.status === "fulfilled" && u.value.id === s.id
        );
        if (
          fulfilled &&
          fulfilled.status === "fulfilled" &&
          fulfilled.value.status !== s.status
        ) {
          changed = true;
          return { ...s, status: fulfilled.value.status };
        }
        return s;
      });
      return changed ? next : prev;
    });
  }, [submissions]);

  // -----------------------------------------------------------------------
  // Effects
  // -----------------------------------------------------------------------

  // Initial load
  useEffect(() => {
    fetchSubmissions();
  }, [fetchSubmissions]);

  // Set up polling
  useEffect(() => {
    const hasPending = submissions.some((s) => !isFinalStatus(s.status));
    if (hasPending) {
      pollRef.current = setInterval(pollStatuses, POLL_INTERVAL_MS);
    }
    return () => {
      if (pollRef.current) {
        clearInterval(pollRef.current);
        pollRef.current = null;
      }
    };
  }, [submissions, pollStatuses]);

  // -----------------------------------------------------------------------
  // Date formatter
  // -----------------------------------------------------------------------

  const formatDate = (iso: string): string => {
    try {
      return new Intl.DateTimeFormat("en-US", {
        dateStyle: "medium",
        timeStyle: "short",
      }).format(new Date(iso));
    } catch {
      return iso;
    }
  };

  // -----------------------------------------------------------------------
  // Render
  // -----------------------------------------------------------------------

  return (
    <div className="bg-white rounded-xl shadow-sm border border-gray-200 p-6">
      <div className="flex items-center justify-between mb-4">
        <h2 className="text-lg font-semibold text-navy-800">
          Your Submissions
        </h2>
        <button
          type="button"
          onClick={() => {
            setLoading(true);
            fetchSubmissions();
          }}
          className="text-sm text-navy-600 hover:text-navy-800 font-medium transition-colors"
        >
          Refresh
        </button>
      </div>

      {/* Loading state */}
      {loading && (
        <div className="py-12 text-center">
          <div className="w-8 h-8 border-4 border-navy-200 border-t-navy-700 rounded-full animate-spin mx-auto" />
          <p className="mt-3 text-sm text-gray-500">Loading submissions...</p>
        </div>
      )}

      {/* Empty state */}
      {!loading && submissions.length === 0 && (
        <div className="py-12 text-center">
          <div className="mx-auto w-14 h-14 mb-4 flex items-center justify-center rounded-full bg-gray-100 text-gray-400">
            <svg
              xmlns="http://www.w3.org/2000/svg"
              className="h-7 w-7"
              fill="none"
              viewBox="0 0 24 24"
              stroke="currentColor"
              strokeWidth={1.5}
            >
              <path
                strokeLinecap="round"
                strokeLinejoin="round"
                d="M9 12h6m-6 4h6m2 5H7a2 2 0 01-2-2V5a2 2 0 012-2h5.586a1 1 0 01.707.293l5.414 5.414a1 1 0 01.293.707V19a2 2 0 01-2 2z"
              />
            </svg>
          </div>
          <p className="text-sm text-gray-500">
            No submissions yet. Upload a file to get started.
          </p>
        </div>
      )}

      {/* Table */}
      {!loading && submissions.length > 0 && (
        <div className="overflow-x-auto -mx-6">
          <table className="min-w-full divide-y divide-gray-200">
            <thead>
              <tr className="bg-gray-50">
                <th className="px-6 py-3 text-left text-xs font-semibold text-gray-500 uppercase tracking-wider">
                  File Name
                </th>
                <th className="px-6 py-3 text-left text-xs font-semibold text-gray-500 uppercase tracking-wider">
                  Course
                </th>
                <th className="px-6 py-3 text-left text-xs font-semibold text-gray-500 uppercase tracking-wider">
                  Upload Date
                </th>
                <th className="px-6 py-3 text-left text-xs font-semibold text-gray-500 uppercase tracking-wider">
                  Status
                </th>
                <th className="px-6 py-3 text-left text-xs font-semibold text-gray-500 uppercase tracking-wider">
                  Actions
                </th>
              </tr>
            </thead>
            <tbody className="bg-white divide-y divide-gray-100">
              {submissions.map((sub) => (
                <tr
                  key={sub.id}
                  className="hover:bg-gray-50 transition-colors"
                >
                  <td className="px-6 py-4 whitespace-nowrap text-sm font-medium text-navy-700">
                    {sub.fileName}
                  </td>
                  <td className="px-6 py-4 whitespace-nowrap text-sm text-gray-600">
                    {sub.courseId}
                    {sub.sectionId ? ` / ${sub.sectionId}` : ""}
                  </td>
                  <td className="px-6 py-4 whitespace-nowrap text-sm text-gray-500">
                    {formatDate(sub.uploadDate)}
                  </td>
                  <td className="px-6 py-4 whitespace-nowrap">
                    <StatusBadge status={sub.status} />
                  </td>
                  <td className="px-6 py-4 whitespace-nowrap text-sm">
                    {sub.status === "complete" && sub.resultUrl ? (
                      <a
                        href={sub.resultUrl}
                        target="_blank"
                        rel="noopener noreferrer"
                        className="text-navy-600 hover:text-navy-800 font-medium transition-colors"
                      >
                        View Report
                      </a>
                    ) : (
                      <span className="text-gray-400">&mdash;</span>
                    )}
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}
    </div>
  );
};

export default SubmissionList;
