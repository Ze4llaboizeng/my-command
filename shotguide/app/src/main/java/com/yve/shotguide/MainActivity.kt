package com.yve.shotguide

import android.Manifest
import android.content.ContentValues
import android.content.pm.PackageManager
import android.hardware.Sensor
import android.hardware.SensorEvent
import android.hardware.SensorEventListener
import android.hardware.SensorManager
import android.os.Build
import android.os.Bundle
import android.provider.MediaStore
import android.widget.Button
import android.widget.TextView
import android.widget.Toast
import androidx.activity.ComponentActivity
import androidx.activity.result.contract.ActivityResultContracts
import androidx.camera.core.Camera
import androidx.camera.core.CameraSelector
import androidx.camera.core.ImageAnalysis
import androidx.camera.core.ImageCapture
import androidx.camera.core.ImageCaptureException
import androidx.camera.core.Preview
import androidx.camera.lifecycle.ProcessCameraProvider
import androidx.camera.view.PreviewView
import androidx.core.content.ContextCompat
import java.text.SimpleDateFormat
import java.util.Locale
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors
import kotlin.math.atan2

class MainActivity : ComponentActivity(), SensorEventListener {
    private lateinit var previewView: PreviewView
    private lateinit var overlayView: GuidanceOverlayView
    private lateinit var lensText: TextView
    private lateinit var adviceText: TextView
    private lateinit var debugText: TextView
    private lateinit var cameraExecutor: ExecutorService
    private lateinit var sensorManager: SensorManager
    private var analyzer: CameraAnalyzer? = null
    private var imageCapture: ImageCapture? = null
    private var camera: Camera? = null
    private var rollDegrees = 0f
    private var gravityX = 0f
    private var gravityY = 0f
    private var currentRecommendation = CoachRecommendation(23,"General",listOf("จัดเฟรมให้นิ่ง"))
    private val cameraPermission=registerForActivityResult(ActivityResultContracts.RequestPermission()){granted->if(granted)startCamera() else Toast.makeText(this,"ต้องอนุญาตกล้องก่อนใช้งาน",Toast.LENGTH_LONG).show()}

    override fun onCreate(savedInstanceState:Bundle?){
        super.onCreate(savedInstanceState); setContentView(R.layout.activity_main)
        previewView=findViewById(R.id.previewView); overlayView=findViewById(R.id.overlayView); lensText=findViewById(R.id.lensText); adviceText=findViewById(R.id.adviceText); debugText=findViewById(R.id.debugText)
        cameraExecutor=Executors.newSingleThreadExecutor(); sensorManager=getSystemService(SENSOR_SERVICE) as SensorManager
        wireLensButton(R.id.lens15,15); wireLensButton(R.id.lens23,23); wireLensButton(R.id.lens35,35); wireLensButton(R.id.lens46,46); wireLensButton(R.id.lens75,75); wireLensButton(R.id.lens115,115)
        findViewById<Button>(R.id.applyRecommendedButton).setOnClickListener{applyFocalLength(currentRecommendation.focalMm)}
        findViewById<Button>(R.id.shutterButton).setOnClickListener{takePhoto()}
        if(ContextCompat.checkSelfPermission(this,Manifest.permission.CAMERA)==PackageManager.PERMISSION_GRANTED)startCamera() else cameraPermission.launch(Manifest.permission.CAMERA)
    }
    override fun onResume(){super.onResume();sensorManager.getDefaultSensor(Sensor.TYPE_ACCELEROMETER)?.also{sensorManager.registerListener(this,it,SensorManager.SENSOR_DELAY_UI)}}
    override fun onPause(){sensorManager.unregisterListener(this);super.onPause()}
    private fun startCamera(){
        val future=ProcessCameraProvider.getInstance(this); future.addListener({
            val provider=future.get(); val preview=Preview.Builder().build().also{it.setSurfaceProvider(previewView.surfaceProvider)}
            imageCapture=ImageCapture.Builder().setCaptureMode(ImageCapture.CAPTURE_MODE_MINIMIZE_LATENCY).build()
            analyzer?.close(); analyzer=CameraAnalyzer{frame->runOnUiThread{currentRecommendation=ShotCoach.recommend(frame,rollDegrees);renderRecommendation(frame,currentRecommendation)}}
            val analysis=ImageAnalysis.Builder().setBackpressureStrategy(ImageAnalysis.STRATEGY_KEEP_ONLY_LATEST).build().also{it.setAnalyzer(cameraExecutor,analyzer!!)}
            try{provider.unbindAll();camera=provider.bindToLifecycle(this,CameraSelector.DEFAULT_BACK_CAMERA,preview,imageCapture,analysis)}catch(e:Exception){Toast.makeText(this,"เปิดกล้องไม่สำเร็จ: ${e.message}",Toast.LENGTH_LONG).show()}
        },ContextCompat.getMainExecutor(this))
    }
    private fun renderRecommendation(frame:FrameAnalysis,rec:CoachRecommendation){lensText.text="${rec.sceneName} • แนะนำ ${rec.focalMm}mm";adviceText.text=rec.advice.joinToString("\n");overlayView.targetX=rec.targetX;overlayView.targetY=rec.targetY;val labels=frame.labels.take(3).joinToString{"${it.first} ${(it.second*100).toInt()}%"};debugText.text="แสง ${frame.luminance.toInt()} | หน้า ${frame.faces.size}"+(if(labels.isNotBlank())" | $labels" else "")}
    private fun wireLensButton(id:Int,focalMm:Int){findViewById<Button>(id).setOnClickListener{applyFocalLength(focalMm)}}
    private fun applyFocalLength(focalMm:Int){val cam=camera?:return;val desired=focalMm/23f;val state=cam.cameraInfo.zoomState.value?:return;val actual=desired.coerceIn(state.minZoomRatio,state.maxZoomRatio);cam.cameraControl.setZoomRatio(actual);Toast.makeText(this,"${focalMm}mm ≈ ${"%.2f".format(actual)}x",Toast.LENGTH_SHORT).show()}
    private fun takePhoto(){
        val capture=imageCapture?:return;val name="SHOTGUIDE_"+SimpleDateFormat("yyyyMMdd_HHmmss",Locale.US).format(System.currentTimeMillis());val values=ContentValues().apply{put(MediaStore.MediaColumns.DISPLAY_NAME,name);put(MediaStore.MediaColumns.MIME_TYPE,"image/jpeg");if(Build.VERSION.SDK_INT>=Build.VERSION_CODES.Q)put(MediaStore.Images.Media.RELATIVE_PATH,"Pictures/ShotGuide")}
        val options=ImageCapture.OutputFileOptions.Builder(contentResolver,MediaStore.Images.Media.EXTERNAL_CONTENT_URI,values).build()
        capture.takePicture(options,ContextCompat.getMainExecutor(this),object:ImageCapture.OnImageSavedCallback{override fun onImageSaved(r:ImageCapture.OutputFileResults){Toast.makeText(this@MainActivity,"บันทึกรูปแล้ว ✓",Toast.LENGTH_SHORT).show()};override fun onError(e:ImageCaptureException){Toast.makeText(this@MainActivity,"ถ่ายไม่สำเร็จ: ${e.message}",Toast.LENGTH_LONG).show()}})
    }
    override fun onSensorChanged(event:SensorEvent){if(event.sensor.type!=Sensor.TYPE_ACCELEROMETER)return;val alpha=.88f;gravityX=alpha*gravityX+(1-alpha)*event.values[0];gravityY=alpha*gravityY+(1-alpha)*event.values[1];rollDegrees=Math.toDegrees(atan2(gravityX.toDouble(),gravityY.toDouble())).toFloat();if(rollDegrees>90)rollDegrees-=180;if(rollDegrees< -90)rollDegrees+=180;overlayView.rollDegrees=rollDegrees}
    override fun onAccuracyChanged(sensor:Sensor?,accuracy:Int)=Unit
    override fun onDestroy(){analyzer?.close();cameraExecutor.shutdown();super.onDestroy()}
}
