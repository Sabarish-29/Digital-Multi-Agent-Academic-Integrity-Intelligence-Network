import axios, { AxiosProgressEvent } from "axios";
import { getAuthToken } from "./auth";

// ---------------------------------------------------------------------------
// Axios instance – base URL read from environment
// ---------------------------------------------------------------------------

const api = axios.create({
  baseURL: process.env.REACT_APP_API_URL || "http://localhost:8000",
  headers: {
    "Content-Type": "application/json",
  },
});

// Attach Cognito JWT to every outgoing request
api.interceptors.request.use(async (config) => {
  const token = await getAuthToken();
  if (token) {
    config.headers.Authorization = `Bearer ${token}`;
  }
  return config;
});

// ---------------------------------------------------------------------------
// Types
// ---------------------------------------------------------------------------

export interface SubmissionMetadata {
  studentId: string;
  courseId: string;
  sectionId: string;
}

export type SubmissionStatus =
  | "uploaded"
  | "processing"
  | "complete"
  | "failed";

export interface Submission {
  id: string;
  fileName: string;
  courseId: string;
  sectionId: string;
  studentId: string;
  uploadDate: string;
  status: SubmissionStatus;
  resultUrl?: string;
}

export interface UploadResponse {
  submissionId: string;
  message: string;
}

// ---------------------------------------------------------------------------
// API functions
// ---------------------------------------------------------------------------

/**
 * Upload a file along with metadata.  Accepts an optional progress callback
 * that receives a value between 0 and 100.
 */
export async function uploadFile(
  file: File,
  metadata: SubmissionMetadata,
  onProgress?: (percent: number) => void
): Promise<UploadResponse> {
  const formData = new FormData();
  formData.append("file", file);
  formData.append("studentId", metadata.studentId);
  formData.append("courseId", metadata.courseId);
  formData.append("sectionId", metadata.sectionId);

  const response = await api.post<UploadResponse>(
    "/submissions/upload",
    formData,
    {
      headers: { "Content-Type": "multipart/form-data" },
      onUploadProgress: (event: AxiosProgressEvent) => {
        if (onProgress && event.total) {
          const percent = Math.round((event.loaded * 100) / event.total);
          onProgress(percent);
        }
      },
    }
  );

  return response.data;
}

/**
 * Fetch a single submission by ID.
 */
export async function getSubmission(id: string): Promise<Submission> {
  const response = await api.get<Submission>(`/submissions/${id}`);
  return response.data;
}

/**
 * Fetch only the status of a submission.
 */
export async function getSubmissionStatus(
  id: string
): Promise<{ status: SubmissionStatus }> {
  const response = await api.get<{ status: SubmissionStatus }>(
    `/submissions/${id}/status`
  );
  return response.data;
}

/**
 * List all submissions visible to the current user.
 */
export async function listSubmissions(): Promise<Submission[]> {
  const response = await api.get<Submission[]>("/submissions");
  return response.data;
}

export default api;
