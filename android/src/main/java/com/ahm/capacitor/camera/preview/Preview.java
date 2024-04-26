package com.ahm.capacitor.camera.preview;

import android.app.Activity;
import android.content.Context;
import android.graphics.SurfaceTexture;
import android.hardware.Camera;
import android.util.DisplayMetrics;
import android.util.Log;
import android.view.Surface;
import android.view.SurfaceHolder;
import android.view.TextureView;
import android.view.View;
import android.widget.RelativeLayout;
import java.io.IOException;
import java.util.ArrayList;
import java.util.List;
import java.util.Collections;

class Preview extends RelativeLayout implements SurfaceHolder.Callback, TextureView.SurfaceTextureListener {

    private final String TAG = "Preview";

    CustomSurfaceView mSurfaceView;
    CustomTextureView mTextureView;
    SurfaceHolder mHolder;
    SurfaceTexture mSurface;
    Camera.Size mPreviewSize;
    List<Camera.Size> mSupportedPreviewSizes = new ArrayList<>();
    Camera mCamera;
    int cameraId;
    int displayOrientation;
    int facing = Camera.CameraInfo.CAMERA_FACING_BACK;
    int viewWidth;
    int viewHeight;
    private boolean enableOpacity = false;
    private float opacity = 1F;

    private final CameraActivity fragment;

    Preview(Context context, boolean enableOpacity, CameraActivity cameraActivity) {
        super(context);
        this.enableOpacity = enableOpacity;
        if (!enableOpacity) {
            mSurfaceView = new CustomSurfaceView(context);
            addView(mSurfaceView);
            requestLayout();

            // Install a SurfaceHolder.Callback so we get notified when the
            // underlying surface is created and destroyed.
            mHolder = mSurfaceView.getHolder();
            mHolder.addCallback(this);
            mHolder.setType(SurfaceHolder.SURFACE_TYPE_PUSH_BUFFERS);
        } else {
            // Use a TextureView so we can manage opacity
            mTextureView = new CustomTextureView(context);
            // Install a SurfaceTextureListener so we get notified
            mTextureView.setSurfaceTextureListener(this);
            mTextureView.setLayerType(View.LAYER_TYPE_HARDWARE, null);
            addView(mTextureView);
            requestLayout();
        }
        fragment = cameraActivity;
    }

    public void setCamera(Camera camera, int cameraId) {
        mCamera = camera;

        if (camera != null) {
            this.cameraId = cameraId;
            mSupportedPreviewSizes = mCamera.getParameters().getSupportedPreviewSizes();
            setCameraDisplayOrientation();

            List<String> mFocusModes = mCamera.getParameters().getSupportedFocusModes();

            Camera.Parameters params = mCamera.getParameters();
            if (mFocusModes.contains("continuous-picture")) {
                params.setFocusMode(Camera.Parameters.FOCUS_MODE_CONTINUOUS_PICTURE);
            } else if (mFocusModes.contains("continuous-video")) {
                params.setFocusMode(Camera.Parameters.FOCUS_MODE_CONTINUOUS_VIDEO);
            } else if (mFocusModes.contains("auto")) {
                params.setFocusMode(Camera.Parameters.FOCUS_MODE_AUTO);
            }
            mCamera.setParameters(params);
        }
    }

    public int getDisplayOrientation() {
        return displayOrientation;
    }

    public int getCameraFacing() {
        return facing;
    }

    public void printPreviewSize(String from) {
        Log.d(TAG, "printPreviewSize from " + from + ": > width: " + mPreviewSize.width + " height: " + mPreviewSize.height);
    }

    public void setCameraPreviewSize() {
        if (mCamera != null) {
            Camera.Parameters parameters = mCamera.getParameters();
            parameters.setPreviewSize(mPreviewSize.width, mPreviewSize.height);
            mCamera.setParameters(parameters);
        }
    }

    public void setCameraDisplayOrientation() {
        Camera.CameraInfo info = new Camera.CameraInfo();
        int rotation = ((Activity) getContext()).getWindowManager().getDefaultDisplay().getRotation();
        int degrees = 0;
        DisplayMetrics dm = new DisplayMetrics();

        Camera.getCameraInfo(cameraId, info);
        ((Activity) getContext()).getWindowManager().getDefaultDisplay().getMetrics(dm);

        switch (rotation) {
            case Surface.ROTATION_0:
                degrees = 0;
                break;
            case Surface.ROTATION_90:
                degrees = 90;
                break;
            case Surface.ROTATION_180:
                degrees = 180;
                break;
            case Surface.ROTATION_270:
                degrees = 270;
                break;
        }
        facing = info.facing;
        if (info.facing == Camera.CameraInfo.CAMERA_FACING_FRONT) {
            displayOrientation = (info.orientation + degrees) % 360;
            displayOrientation = (360 - displayOrientation) % 360;
        } else {
            displayOrientation = (info.orientation - degrees + 360) % 360;
        }

        Log.d(TAG, "screen is rotated " + degrees + "deg from natural");
        Log.d(
                TAG,
                (info.facing == Camera.CameraInfo.CAMERA_FACING_FRONT ? "front" : "back") +
                        " camera is oriented -" +
                        info.orientation +
                        "deg from natural"
        );
        Log.d(TAG, "need to rotate preview " + displayOrientation + "deg");

        if(mCamera != null) {
            mCamera.setDisplayOrientation(displayOrientation);
        }
    }

    public void switchCamera(Camera camera, int cameraId) {
        try {
            setCamera(camera, cameraId);

            Log.d("CameraPreview", "before set camera");

            View v;
            if (enableOpacity) {
                camera.setPreviewTexture(mSurface);
                v = mTextureView;
            } else {
                camera.setPreviewDisplay(mHolder);
                v = mSurfaceView;
            }

            Log.d("CameraPreview", "before getParameters");

            Camera.Parameters parameters = camera.getParameters();

            Log.d("CameraPreview", "before setPreviewSize");

            mSupportedPreviewSizes = parameters.getSupportedPreviewSizes();
            mPreviewSize = getOptimalPreviewSize(mSupportedPreviewSizes, v.getWidth(), v.getHeight());
            parameters.setPreviewSize(mPreviewSize.width, mPreviewSize.height);
            Log.d(TAG, mPreviewSize.width + " " + mPreviewSize.height);

            camera.setParameters(parameters);
        } catch (IOException exception) {
            Log.e(TAG, exception.getMessage());
        }
    }

    @Override
    protected void onMeasure(int widthMeasureSpec, int heightMeasureSpec) {
        // We purposely disregard child measurements because act as a
        // wrapper to a SurfaceView that centers the camera preview instead
        // of stretching it.
        final int width = resolveSize(getSuggestedMinimumWidth(), widthMeasureSpec);
        final int height = resolveSize(getSuggestedMinimumHeight(), heightMeasureSpec);
        setMeasuredDimension(width, height);

        mPreviewSize = getOptimalPreviewSize(mSupportedPreviewSizes, width, height);
    }

    @Override
    protected void onLayout(boolean changed, int l, int t, int r, int b) {
        if (changed && getChildCount() > 0) {
            final View child = getChildAt(0);

            int width = r - l;
            int height = b - t;

            int previewWidth = width;
            int previewHeight = height;

            if (mPreviewSize != null) {
                previewWidth = mPreviewSize.width;
                previewHeight = mPreviewSize.height;

                if (displayOrientation == 90 || displayOrientation == 270) {
                    previewWidth = mPreviewSize.height;
                    previewHeight = mPreviewSize.width;
                }
                //LOG.d(TAG, "previewWidth:" + previewWidth + " previewHeight:" + previewHeight);
            }

            int nW;
            int nH;
            int top;
            int left;

            float scale = 1.0f;

            // Center the child SurfaceView within the parent.
            if (width * previewHeight < height * previewWidth) {
                Log.d(TAG, "center horizontally");
                int scaledChildWidth = (int) ((previewWidth * height / previewHeight) * scale);
                nW = (width + scaledChildWidth) / 2;
                nH = (int) (height * scale);
                top = 0;
                left = (width - scaledChildWidth) / 2;
            } else {
                Log.d(TAG, "center vertically");
                int scaledChildHeight = (int) ((previewHeight * width / previewWidth) * scale);
                nW = (int) (width * scale);
                nH = (height + scaledChildHeight) / 2;
                top = (height - scaledChildHeight) / 2;
                left = 0;
            }
            child.layout(left, top, nW, nH);

            Log.d("layout", "left:" + left);
            Log.d("layout", "top:" + top);
            Log.d("layout", "right:" + nW);
            Log.d("layout", "bottom:" + nH);
        }
    }

    public void surfaceCreated(SurfaceHolder holder) {
        // The Surface has been created, acquire the camera and tell it where
        // to draw.
        try {
            if (mCamera != null) {
                mSurfaceView.setWillNotDraw(false);
                mCamera.setPreviewDisplay(holder);
            }
        } catch (Exception exception) {
            Log.e(TAG, "Exception caused by setPreviewDisplay()", exception);
        }
    }

    public void surfaceDestroyed(SurfaceHolder holder) {
        // Surface will be destroyed when we return, so stop the preview.
        try {
            if (mCamera != null) {
                mCamera.stopPreview();
            }
        } catch (Exception exception) {
            Log.e(TAG, "Exception caused by surfaceDestroyed()", exception);
        }
    }

    public void surfaceChanged(SurfaceHolder holder, int format, int w, int h) {
        mSupportedPreviewSizes = mCamera.getParameters().getSupportedPreviewSizes();

        List<Camera.Size> sizes = new ArrayList<>(mSupportedPreviewSizes);
        sortSizesToMatchAspectRatio(w, h, sizes);

        for(Camera.Size size : sizes) {
            if(!isSizeMatchingAspectRatio(w, h, size, 0.1)) break;

            if (trySetPreviewSize(size)) {
                mCamera.startPreview();
                return;
            }
        }

        restartCamera();
    }

    private boolean isSizeMatchingAspectRatio(int w, int h, Camera.Size size, double aspectTolerance)
    {
        double targetRatio = computeTargetRatio(w, h);
        double ratio = (double) size.width / size.height;
        return (Math.abs(ratio - targetRatio) < aspectTolerance);
    }

    private boolean trySetPreviewSize(Camera.Size size) {
        Camera.Parameters parameters = mCamera.getParameters();
        Camera.Size rollbackValue = parameters.getPreviewSize();
        Log.d(TAG, "trySetPreviewSize : " + size.width + "   " + size.height);

        try {
            mPreviewSize = size;
            parameters.setPreviewSize(size.width, size.height);
            requestLayout();
            mCamera.setParameters(parameters);
        } catch (RuntimeException exception) {
            Log.w(TAG, "trySetPreviewSize failed with: " + exception);
            mPreviewSize = rollbackValue;
            parameters.setPreviewSize(rollbackValue.width, rollbackValue.height);
            requestLayout();

            if(exception.getMessage() != null && exception.getMessage().contains("setParameters failed")) {
                return false;
            }
            else {
                Log.e(TAG, "Exception caused by surfaceChanged()", exception);
            }
        }
        return true;
    }

    private void restartCamera() {
        Log.w(TAG, "no fitting preview size found - restarting camera");
        fragment.onPause();
        fragment.onResume();
    }

    private void startCamera() {
        Camera.Parameters parameters = mCamera.getParameters();
        parameters.setPreviewSize(mPreviewSize.width, mPreviewSize.height);
        requestLayout();
        //mCamera.setDisplayOrientation(90);
        mCamera.setParameters(parameters);
        mCamera.startPreview();
    }

    //  Texture Callbacks

    public void onSurfaceTextureAvailable(SurfaceTexture surface, int width, int height) {
        // The Surface has been created, acquire the camera and tell it where
        // to draw.
        try {
            mSurface = surface;
            mPreviewSize = getOptimalPreviewSize(mSupportedPreviewSizes, width, height);

            if (mCamera != null) {
                mTextureView.setAlpha(opacity);
                mCamera.setPreviewTexture(surface);
                startCamera();
            }
        } catch (Exception exception) {
            Log.e(TAG, "Exception caused by onSurfaceTextureAvailable()", exception);
        }
    }

    private Camera.Size getOptimalPreviewSize(List<Camera.Size> sizes, int w, int h) {
        List<Camera.Size> sorted = new ArrayList<Camera.Size>(sizes);
        sortSizesToMatchAspectRatio(w, h, sorted);

        if(sorted.isEmpty())
            return null;

        Camera.Size optimalSize = sorted.get(0);
        Log.d(TAG, "optimal preview size: w: " + optimalSize.width + " h: " + optimalSize.height);
        return optimalSize;
    }

    public void sortSizesToMatchAspectRatio(int w, int h, List<Camera.Size> sizes) {
        if(sizes.size() <= 1) {
            return;
        }

        double targetRatio = computeTargetRatio(w, h);
        double targetHeight = computeTargetHeight(w, h);
        double ratioDiffThresholdToConsiderHeight = 0.1;

        Collections.sort(sizes, (size1, size2) -> {
            double ratio1 = (double) size1.width / size1.height;
            double ratio2 = (double) size2.width / size2.height;
            double ratioDiff1 = Math.abs(ratio1 - targetRatio);
            double ratioDiff2 = Math.abs(ratio2 - targetRatio);

            // for preview sizes with very similar aspect ratio: compare target height instead
            if(Math.abs(ratioDiff1 - ratioDiff2) < ratioDiffThresholdToConsiderHeight) {
                double heightDiff1 = Math.abs(size1.height - targetHeight);
                double heightDiff2 = Math.abs(size2.height - targetHeight);
                return Double.compare(heightDiff1, heightDiff2);
            }
            return Double.compare(ratioDiff1, ratioDiff2);
        });
    }

    private double computeTargetRatio(int w, int h) {
        return (displayOrientation == 0 || displayOrientation == 180) ? (double) w / h : (double) h / w;
    }

    private double computeTargetHeight(int w, int h) {
        return (displayOrientation == 0 || displayOrientation == 180) ? h : w;
    }

    public void onSurfaceTextureSizeChanged(SurfaceTexture surface, int width, int height) {}

    public boolean onSurfaceTextureDestroyed(SurfaceTexture surface) {
        try {
            if (mCamera != null) {
                mCamera.stopPreview();
            }
        } catch (Exception exception) {
            Log.e(TAG, "Exception caused by onSurfaceTextureDestroyed()", exception);
            return false;
        }
        return true;
    }

    public void onSurfaceTextureUpdated(SurfaceTexture surface) {}

    public void setOneShotPreviewCallback(Camera.PreviewCallback callback) {
        if (mCamera != null) {
            mCamera.setOneShotPreviewCallback(callback);
        }
    }

    public void setOpacity(final float opacity) {
        this.opacity = opacity;
        if (mCamera != null && enableOpacity) {
            mTextureView.setAlpha(opacity);
        }
    }
}
