package com.yve.shotguide

import kotlin.math.abs

object ShotCoach {
    private val wideWords=setOf("landscape","sky","mountain","building","architecture","room","interior","city","bridge","tower","road","nature","beach")
    private val foodWords=setOf("food","dish","meal","cuisine","dessert","fruit","drink","tableware")
    private val closeWords=setOf("flower","plant","product","toy","watch","jewellery","jewelry")
    private val streetWords=setOf("street","vehicle","car","motorcycle","bicycle","market","crowd")
    fun recommend(frame:FrameAnalysis,rollDegrees:Float):CoachRecommendation {
        val labels=frame.labels.map{it.first.lowercase()}.toSet(); val advice=mutableListOf<String>()
        if(abs(rollDegrees)>1.6f) advice += if(rollDegrees>0) "หมุนเครื่องทวนเข็มนิดหนึ่ง (${abs(rollDegrees).toInt()}°) ให้เส้นตรง" else "หมุนเครื่องตามเข็มนิดหนึ่ง (${abs(rollDegrees).toInt()}°) ให้เส้นตรง"
        if(frame.luminance<62.0){ advice += "แสงน้อย ใช้ 23mm จะได้เปรียบเรื่องความสว่างและความนิ่ง"; return CoachRecommendation(23,"Low light",advice.take(3)) }
        if(frame.faces.isNotEmpty()) {
            val main=frame.faces.maxBy{it.areaRatio}; val tx=if(main.centerX<.5f)1f/3f else 2f/3f; val ty=1f/3f
            val dx=tx-main.centerX; val dy=ty-main.centerY
            if(abs(dx)>.065f) advice += if(dx>0) "วางใบหน้าไปทางขวาอีกนิด ให้เข้าเส้น 1/3" else "วางใบหน้าไปทางซ้ายอีกนิด ให้เข้าเส้น 1/3"
            if(abs(dy)>.07f) advice += if(dy>0) "ลดตำแหน่งใบหน้าลงเล็กน้อย" else "ยกตำแหน่งใบหน้าขึ้นใกล้เส้น 1/3 ด้านบน"
            val focal=when { main.areaRatio>.20f->46; main.areaRatio>.075f->75; else->115 }
            if(advice.isEmpty()) advice += "เฟรมดีแล้ว รักษาระยะและล็อกโฟกัสที่ตา"
            return CoachRecommendation(focal,"Portrait",advice.take(3),tx,ty)
        }
        val focal=when { labels.any{it in wideWords}->15; labels.any{it in foodWords}->46; labels.any{it in closeWords}->46; labels.any{it in streetWords}->35; else->23 }
        val scene=when(focal){15->"Landscape / Architecture";35->"Street";46->"Food / Detail";else->"General"}
        if(advice.isEmpty()) advice += when(focal){15->"ใช้เส้นนำสายตาเข้าหาจุดเด่น และระวังคนชิดขอบภาพ";35->"เก็บบริบทรอบตัว แต่ไม่ให้ฉากหลังแย่ง subject";46->"เข้าใกล้รายละเอียด แล้ววางจุดเด่นใกล้จุดตัด 1/3";else->"ขยับจุดเด่นออกจากกึ่งกลางเล็กน้อย แล้วเช็กฉากหลัง"}
        return CoachRecommendation(focal,scene,advice.take(3))
    }
}
