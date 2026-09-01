package com.yve.shotguide

import androidx.camera.core.ImageAnalysis
import androidx.camera.core.ImageProxy
import com.google.android.gms.tasks.Tasks
import com.google.mlkit.vision.common.InputImage
import com.google.mlkit.vision.face.FaceDetection
import com.google.mlkit.vision.face.FaceDetectorOptions
import com.google.mlkit.vision.label.ImageLabeling
import com.google.mlkit.vision.label.defaults.ImageLabelerOptions
import java.util.concurrent.atomic.AtomicBoolean

class CameraAnalyzer(private val onResult: (FrameAnalysis) -> Unit) : ImageAnalysis.Analyzer {
    private val busy=AtomicBoolean(false); private var lastAnalyzeMs=0L
    private val faceDetector=FaceDetection.getClient(FaceDetectorOptions.Builder().setPerformanceMode(FaceDetectorOptions.PERFORMANCE_MODE_FAST).enableTracking().setMinFaceSize(0.10f).build())
    private val labeler=ImageLabeling.getClient(ImageLabelerOptions.Builder().setConfidenceThreshold(0.62f).build())
    override fun analyze(imageProxy: ImageProxy) {
        val now=System.currentTimeMillis(); if(now-lastAnalyzeMs<240 || !busy.compareAndSet(false,true)){imageProxy.close();return}; lastAnalyzeMs=now
        val mediaImage=imageProxy.image ?: run {busy.set(false);imageProxy.close();return}
        val rotation=imageProxy.imageInfo.rotationDegrees; val input=InputImage.fromMediaImage(mediaImage,rotation); val luminance=estimateLuminance(imageProxy)
        val faceTask=faceDetector.process(input); val labelTask=labeler.process(input)
        Tasks.whenAllComplete(faceTask,labelTask).addOnCompleteListener {
            try {
                val rw=if(rotation==90||rotation==270) imageProxy.height else imageProxy.width; val rh=if(rotation==90||rotation==270) imageProxy.width else imageProxy.height
                val faces=if(faceTask.isSuccessful) faceTask.result.orEmpty().map { f -> val b=f.boundingBox; FaceInfo((b.exactCenterX()/rw).coerceIn(0f,1f),(b.exactCenterY()/rh).coerceIn(0f,1f),((b.width().toFloat()*b.height())/(rw.toFloat()*rh)).coerceIn(0f,1f),f.headEulerAngleY) } else emptyList()
                val labels=if(labelTask.isSuccessful) labelTask.result.orEmpty().sortedByDescending{it.confidence}.take(5).map{it.text to it.confidence} else emptyList()
                onResult(FrameAnalysis(faces,labels,luminance))
            } finally { busy.set(false); imageProxy.close() }
        }
    }
    private fun estimateLuminance(imageProxy:ImageProxy):Double { val buffer=imageProxy.planes.firstOrNull()?.buffer?:return 128.0; val d=buffer.duplicate(); val remaining=d.remaining(); if(remaining<=0)return 128.0; val step=(remaining/1500).coerceAtLeast(1); var sum=0L; var count=0; var i=d.position(); val limit=d.limit(); while(i<limit){sum += d.get(i).toInt() and 0xFF;count++;i+=step}; return if(count==0)128.0 else sum.toDouble()/count }
    fun close(){faceDetector.close();labeler.close()}
}
