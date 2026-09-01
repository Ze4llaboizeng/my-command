package com.yve.shotguide

import android.content.Context
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.util.AttributeSet
import android.view.View
import kotlin.math.abs
import kotlin.math.tan

class GuidanceOverlayView @JvmOverloads constructor(context: Context, attrs: AttributeSet? = null) : View(context, attrs) {
    private val gridPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply { color = Color.argb(125,255,255,255); strokeWidth = 1.5f }
    private val horizonPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply { color = Color.argb(220,255,255,255); strokeWidth = 4f }
    private val targetPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply { color = Color.WHITE; style = Paint.Style.STROKE; strokeWidth = 4f }
    var rollDegrees: Float = 0f; set(value) { field = value.coerceIn(-15f,15f); invalidate() }
    var targetX: Float? = null; set(value) { field = value; invalidate() }
    var targetY: Float? = null; set(value) { field = value; invalidate() }
    override fun onDraw(canvas: Canvas) {
        val w=width.toFloat(); val h=height.toFloat()
        canvas.drawLine(w/3f,0f,w/3f,h,gridPaint); canvas.drawLine(2*w/3f,0f,2*w/3f,h,gridPaint)
        canvas.drawLine(0f,h/3f,w,h/3f,gridPaint); canvas.drawLine(0f,2*h/3f,w,2*h/3f,gridPaint)
        val hw=w*.45f; val cx=w/2; val cy=h/2; val dy=tan(Math.toRadians(rollDegrees.toDouble())).toFloat()*hw/2
        horizonPaint.alpha=if(abs(rollDegrees)<=1.5f)255 else 180
        canvas.drawLine(cx-hw/2,cy-dy,cx+hw/2,cy+dy,horizonPaint)
        val tx=targetX; val ty=targetY
        if(tx!=null&&ty!=null){ val x=tx*w; val y=ty*h; canvas.drawCircle(x,y,28f,targetPaint); canvas.drawLine(x-45,y,x+45,y,targetPaint); canvas.drawLine(x,y-45,x,y+45,targetPaint) }
    }
}
