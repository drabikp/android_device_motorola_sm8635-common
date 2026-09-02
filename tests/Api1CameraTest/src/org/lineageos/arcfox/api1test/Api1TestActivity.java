package org.lineageos.arcfox.api1test;

import android.app.Activity;
import android.hardware.Camera;
import android.media.CamcorderProfile;
import android.media.MediaRecorder;
import android.os.Bundle;
import android.os.Handler;
import android.util.Log;
import android.view.SurfaceHolder;
import android.view.SurfaceView;

import java.io.File;

/**
 * Minimal legacy-Camera (API1) exerciser: preview, then MediaRecorder capture.
 *
 * Every step logs PASS/FAIL under one tag so the result can be read from
 * logcat without a human watching the screen:
 *
 *     adb logcat -s API1TEST
 *
 * Deliberately uses android.hardware.Camera (deprecated API1), NOT camera2.
 */
public class Api1TestActivity extends Activity implements SurfaceHolder.Callback {

    private static final String TAG = "API1TEST";
    private static final int RECORD_MS = 5000;

    private Camera mCamera;
    private MediaRecorder mRecorder;
    private File mOutput;
    private boolean mStarted;

    @Override
    protected void onCreate(Bundle b) {
        super.onCreate(b);
        SurfaceView sv = new SurfaceView(this);
        setContentView(sv);
        sv.getHolder().addCallback(this);
        Log.i(TAG, "RESULT api1_activity_started=PASS");
    }

    @Override
    public void surfaceCreated(SurfaceHolder holder) {
        if (mStarted) return;
        mStarted = true;
        new Thread(() -> run(holder)).start();
    }

    private void run(SurfaceHolder holder) {
        // --- 1. enumeration -------------------------------------------------
        int n = Camera.getNumberOfCameras();
        Log.i(TAG, "RESULT api1_camera_count=" + n + " " + (n > 0 ? "PASS" : "FAIL"));
        if (n <= 0) { finishUp(); return; }

        // --- 2. open --------------------------------------------------------
        try {
            mCamera = Camera.open(0);
            Log.i(TAG, "RESULT api1_open=" + (mCamera != null ? "PASS" : "FAIL"));
        } catch (Throwable t) {
            Log.e(TAG, "RESULT api1_open=FAIL " + t);
            finishUp(); return;
        }
        if (mCamera == null) { finishUp(); return; }

        // --- 3. preview -----------------------------------------------------
        try {
            mCamera.setPreviewDisplay(holder);
            mCamera.startPreview();
            Log.i(TAG, "RESULT api1_preview=PASS");
        } catch (Throwable t) {
            Log.e(TAG, "RESULT api1_preview=FAIL " + t);
            release(); finishUp(); return;
        }

        // --- 4. a real preview frame, not just "startPreview returned" -------
        final Object lock = new Object();
        final boolean[] got = {false};
        try {
            mCamera.setPreviewCallback((data, cam) -> {
                synchronized (lock) {
                    if (!got[0]) {
                        got[0] = true;
                        Log.i(TAG, "RESULT api1_preview_frame=PASS bytes=" + (data == null ? 0 : data.length));
                        lock.notifyAll();
                    }
                }
            });
            synchronized (lock) { if (!got[0]) lock.wait(5000); }
            if (!got[0]) Log.e(TAG, "RESULT api1_preview_frame=FAIL no frame in 5s");
            mCamera.setPreviewCallback(null);
        } catch (Throwable t) {
            Log.e(TAG, "RESULT api1_preview_frame=FAIL " + t);
        }

        // --- 5. video via MediaRecorder bound to the API1 camera -------------
        try {
            mOutput = new File(getExternalFilesDir(null), "api1_video.mp4");
            if (mOutput.exists()) mOutput.delete();

            mCamera.unlock();                      // required before MediaRecorder
            mRecorder = new MediaRecorder();
            mRecorder.setCamera(mCamera);
            mRecorder.setAudioSource(MediaRecorder.AudioSource.CAMCORDER);
            mRecorder.setVideoSource(MediaRecorder.VideoSource.CAMERA);
            CamcorderProfile p = CamcorderProfile.get(0, CamcorderProfile.QUALITY_720P);
            mRecorder.setProfile(p);
            mRecorder.setOutputFile(mOutput.getAbsolutePath());
            mRecorder.setPreviewDisplay(holder.getSurface());
            mRecorder.prepare();
            Log.i(TAG, "RESULT api1_recorder_prepare=PASS");
            mRecorder.start();
            Log.i(TAG, "RESULT api1_recorder_start=PASS profile=" + p.videoFrameWidth + "x" + p.videoFrameHeight);
        } catch (Throwable t) {
            Log.e(TAG, "RESULT api1_video=FAIL " + t);
            release(); finishUp(); return;
        }

        new Handler(getMainLooper()).postDelayed(this::stopAndReport, RECORD_MS);
    }

    private void stopAndReport() {
        try {
            mRecorder.stop();
            Log.i(TAG, "RESULT api1_recorder_stop=PASS");
        } catch (Throwable t) {
            Log.e(TAG, "RESULT api1_recorder_stop=FAIL " + t);
        }
        long size = (mOutput != null && mOutput.exists()) ? mOutput.length() : 0;
        Log.i(TAG, "RESULT api1_video_bytes=" + size + " " + (size > 10000 ? "PASS" : "FAIL"));
        Log.i(TAG, "RESULT api1_video_path=" + (mOutput == null ? "none" : mOutput.getAbsolutePath()));
        release();
        Log.i(TAG, "RESULT api1_done=1");
        finishUp();
    }

    private void release() {
        try { if (mRecorder != null) { mRecorder.reset(); mRecorder.release(); mRecorder = null; } } catch (Throwable ignored) {}
        try { if (mCamera != null) { mCamera.release(); mCamera = null; } } catch (Throwable ignored) {}
    }

    private void finishUp() { runOnUiThread(this::finish); }

    @Override public void surfaceChanged(SurfaceHolder h, int f, int w, int ht) {}
    @Override public void surfaceDestroyed(SurfaceHolder h) { release(); }
}
