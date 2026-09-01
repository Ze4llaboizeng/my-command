package com.yve.shotguide

data class FaceInfo(val centerX: Float, val centerY: Float, val areaRatio: Float, val headEulerY: Float)
data class FrameAnalysis(val faces: List<FaceInfo>, val labels: List<Pair<String, Float>>, val luminance: Double)
data class CoachRecommendation(val focalMm: Int, val sceneName: String, val advice: List<String>, val targetX: Float? = null, val targetY: Float? = null) {
    val zoomRatio: Float get() = focalMm / 23f
}
