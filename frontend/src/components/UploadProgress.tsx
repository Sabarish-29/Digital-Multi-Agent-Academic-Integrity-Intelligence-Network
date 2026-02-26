import React from "react";

// ---------------------------------------------------------------------------
// Props
// ---------------------------------------------------------------------------

interface UploadProgressProps {
  /** File name being uploaded. */
  fileName: string;
  /** Upload percentage (0-100). */
  percent: number;
  /** Optional cancel callback. When provided a Cancel button is rendered. */
  onCancel?: () => void;
}

// ---------------------------------------------------------------------------
// Component
// ---------------------------------------------------------------------------

const UploadProgress: React.FC<UploadProgressProps> = ({
  fileName,
  percent,
  onCancel,
}) => {
  const clampedPercent = Math.min(100, Math.max(0, percent));

  return (
    <div className="mt-4 p-4 bg-blue-50 border border-blue-200 rounded-lg">
      <div className="flex items-center justify-between mb-2">
        <span className="text-sm font-medium text-navy-700 truncate max-w-[70%]">
          {fileName}
        </span>
        <span className="text-sm font-semibold text-navy-800">
          {clampedPercent}%
        </span>
      </div>

      {/* Progress bar track */}
      <div className="w-full h-2.5 bg-blue-100 rounded-full overflow-hidden">
        <div
          className="h-full bg-blue-600 rounded-full transition-all duration-300 ease-out"
          style={{ width: `${clampedPercent}%` }}
        />
      </div>

      {/* Cancel button */}
      {onCancel && (
        <div className="mt-2 text-right">
          <button
            type="button"
            onClick={onCancel}
            className="text-xs text-red-600 hover:text-red-800 font-medium transition-colors"
          >
            Cancel upload
          </button>
        </div>
      )}
    </div>
  );
};

export default UploadProgress;
