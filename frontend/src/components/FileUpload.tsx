import React, { useCallback, useState } from "react";
import { useDropzone } from "react-dropzone";
import { toast } from "react-toastify";

import { uploadFile } from "../services/api";
import { useAuth } from "../App";
import UploadProgress from "./UploadProgress";

// ---------------------------------------------------------------------------
// Allowed extensions and max file size
// ---------------------------------------------------------------------------

const ALLOWED_EXTENSIONS = new Set([
  ".pdf",
  ".docx",
  ".txt",
  ".py",
  ".java",
  ".cpp",
  ".c",
  ".js",
  ".html",
  ".css",
  ".ipynb",
  ".tex",
]);

const MAX_FILE_SIZE_BYTES = 50 * 1024 * 1024; // 50 MB

// ---------------------------------------------------------------------------
// Helper
// ---------------------------------------------------------------------------

function getExtension(fileName: string): string {
  const dotIndex = fileName.lastIndexOf(".");
  return dotIndex >= 0 ? fileName.slice(dotIndex).toLowerCase() : "";
}

// ---------------------------------------------------------------------------
// Component
// ---------------------------------------------------------------------------

const FileUpload: React.FC = () => {
  const { userId } = useAuth();

  const [file, setFile] = useState<File | null>(null);
  const [courseId, setCourseId] = useState("");
  const [sectionId, setSectionId] = useState("");
  const [uploading, setUploading] = useState(false);
  const [progress, setProgress] = useState(0);

  // -----------------------------------------------------------------------
  // Dropzone handler
  // -----------------------------------------------------------------------

  const onDrop = useCallback((acceptedFiles: File[]) => {
    if (acceptedFiles.length === 0) return;

    const selected = acceptedFiles[0];
    const ext = getExtension(selected.name);

    if (!ALLOWED_EXTENSIONS.has(ext)) {
      toast.error(
        `Unsupported file type "${ext}". Allowed: ${[...ALLOWED_EXTENSIONS].join(", ")}`
      );
      return;
    }

    if (selected.size > MAX_FILE_SIZE_BYTES) {
      toast.error("File exceeds the 50 MB size limit.");
      return;
    }

    setFile(selected);
  }, []);

  const { getRootProps, getInputProps, isDragActive } = useDropzone({
    onDrop,
    multiple: false,
  });

  // -----------------------------------------------------------------------
  // Upload handler
  // -----------------------------------------------------------------------

  const handleUpload = async () => {
    if (!file) {
      toast.error("Please select a file first.");
      return;
    }
    if (!courseId.trim()) {
      toast.error("Course ID is required.");
      return;
    }
    if (!sectionId.trim()) {
      toast.error("Section ID is required.");
      return;
    }

    setUploading(true);
    setProgress(0);

    try {
      const result = await uploadFile(
        file,
        {
          studentId: userId,
          courseId: courseId.trim(),
          sectionId: sectionId.trim(),
        },
        (pct) => setProgress(pct)
      );

      toast.success(result.message || "File uploaded successfully!");
      // Reset form
      setFile(null);
      setCourseId("");
      setSectionId("");
    } catch (err: unknown) {
      const message =
        err instanceof Error ? err.message : "Upload failed. Please try again.";
      toast.error(message);
    } finally {
      setUploading(false);
      setProgress(0);
    }
  };

  // -----------------------------------------------------------------------
  // Styles
  // -----------------------------------------------------------------------

  const inputClass =
    "w-full px-3 py-2 border border-gray-300 rounded-lg text-sm focus:ring-2 focus:ring-navy-500 focus:border-navy-500 outline-none transition-colors placeholder-gray-400";

  // -----------------------------------------------------------------------
  // Render
  // -----------------------------------------------------------------------

  return (
    <div className="bg-white rounded-xl shadow-sm border border-gray-200 p-6">
      <h2 className="text-lg font-semibold text-navy-800 mb-4">
        Upload Submission
      </h2>

      {/* Dropzone */}
      <div
        {...getRootProps()}
        className={`border-2 border-dashed rounded-xl p-8 text-center cursor-pointer transition-colors ${
          isDragActive
            ? "border-blue-500 bg-blue-50"
            : "border-gray-300 hover:border-navy-400 hover:bg-gray-50"
        }`}
      >
        <input {...getInputProps()} />

        {/* Drop-zone icon */}
        <div className="mx-auto w-12 h-12 mb-3 flex items-center justify-center rounded-full bg-navy-100 text-navy-600">
          <svg
            xmlns="http://www.w3.org/2000/svg"
            className="h-6 w-6"
            fill="none"
            viewBox="0 0 24 24"
            stroke="currentColor"
            strokeWidth={2}
          >
            <path
              strokeLinecap="round"
              strokeLinejoin="round"
              d="M7 16a4 4 0 01-.88-7.903A5 5 0 1115.9 6L16 6a5 5 0 011 9.9M15 13l-3-3m0 0l-3 3m3-3v12"
            />
          </svg>
        </div>

        {file ? (
          <p className="text-sm text-navy-700 font-medium">{file.name}</p>
        ) : isDragActive ? (
          <p className="text-sm text-blue-600 font-medium">
            Drop your file here...
          </p>
        ) : (
          <>
            <p className="text-sm text-gray-600">
              <span className="font-medium text-navy-600">Click to browse</span>{" "}
              or drag and drop
            </p>
            <p className="mt-1 text-xs text-gray-400">
              PDF, DOCX, TXT, PY, JAVA, CPP, C, JS, HTML, CSS, IPYNB, TEX
              &mdash; up to 50 MB
            </p>
          </>
        )}
      </div>

      {/* File info */}
      {file && (
        <div className="mt-3 flex items-center justify-between text-xs text-gray-500">
          <span>{(file.size / 1024 / 1024).toFixed(2)} MB</span>
          <button
            type="button"
            onClick={() => setFile(null)}
            className="text-red-500 hover:text-red-700 font-medium transition-colors"
          >
            Remove
          </button>
        </div>
      )}

      {/* Metadata fields */}
      <div className="mt-5 space-y-3">
        <div>
          <label className="block text-sm font-medium text-gray-700 mb-1">
            Course ID
          </label>
          <input
            type="text"
            value={courseId}
            onChange={(e) => setCourseId(e.target.value)}
            className={inputClass}
            placeholder="e.g. CS-101"
            disabled={uploading}
          />
        </div>
        <div>
          <label className="block text-sm font-medium text-gray-700 mb-1">
            Section ID
          </label>
          <input
            type="text"
            value={sectionId}
            onChange={(e) => setSectionId(e.target.value)}
            className={inputClass}
            placeholder="e.g. 001"
            disabled={uploading}
          />
        </div>
      </div>

      {/* Upload progress */}
      {uploading && (
        <UploadProgress
          fileName={file?.name ?? ""}
          percent={progress}
        />
      )}

      {/* Upload button */}
      <button
        type="button"
        onClick={handleUpload}
        disabled={uploading || !file}
        className="mt-5 w-full py-2.5 px-4 bg-navy-700 hover:bg-navy-800 text-white text-sm font-medium rounded-lg transition-colors disabled:opacity-50 disabled:cursor-not-allowed"
      >
        {uploading ? "Uploading..." : "Upload File"}
      </button>
    </div>
  );
};

export default FileUpload;
