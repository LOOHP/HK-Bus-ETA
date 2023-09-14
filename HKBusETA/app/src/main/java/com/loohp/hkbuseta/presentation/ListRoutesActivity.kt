package com.loohp.hkbuseta.presentation

import android.content.Intent
import android.os.Bundle
import android.text.TextUtils
import android.util.TypedValue
import android.view.View
import android.view.ViewGroup
import android.widget.ScrollView
import android.widget.TableLayout
import android.widget.TableRow
import android.widget.TextView
import android.widget.Toast
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.toArgb
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.wear.compose.material.MaterialTheme
import com.loohp.hkbuseta.R
import com.loohp.hkbuseta.presentation.shared.Shared
import com.loohp.hkbuseta.presentation.theme.HKBusETATheme
import com.loohp.hkbuseta.presentation.utils.JsonUtils
import com.loohp.hkbuseta.presentation.utils.StringUtils
import org.json.JSONArray
import org.json.JSONObject
import kotlin.math.roundToInt


class ListRoutesActivity : ComponentActivity() {

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val list = intent.extras!!.getString("result")?.let { JSONArray(it) } ?: throw RuntimeException()
        val result = JsonUtils.toList(list, JSONObject::class.java)
        setContent {
            ListRoutePage(this, result)
        }
    }
}

@Composable
fun ListRoutePage(instance: ListRoutesActivity, result: List<JSONObject>) {
    HKBusETATheme {
        Column(
            modifier = Modifier
                .fillMaxSize()
                .background(MaterialTheme.colors.background),
            verticalArrangement = Arrangement.Top
        ) {
            Shared.MainTime()
        }
        Column(
            modifier = Modifier
                .fillMaxSize(),
            verticalArrangement = Arrangement.Center
        ) {
            MainElement(instance, result)
        }
    }
}

@Composable
fun MainElement(instance: ListRoutesActivity, result: List<JSONObject>) {
    val haptic = LocalHapticFeedback.current

    instance.setContentView(R.layout.route_list)
    val table: TableLayout = instance.findViewById(R.id.route_list)
    table.removeAllViews()
    for (route in result) {
        val color = when (route.optString("co")) {
            "kmb" -> Color(0xFFFF4747)
            "ctb" -> Color(0xFFFFE15E)
            "nlb" -> Color(0xFF9BFFC6)
            "mtr-bus" -> Color(0xFFAAD4FF)
            "gmb" -> Color(0xFF36FF42)
            else -> Color.White
        }.toArgb()

        val tr = TableRow(instance)
        tr.layoutParams = TableRow.LayoutParams(
            TableRow.LayoutParams.MATCH_PARENT,
            TableRow.LayoutParams.WRAP_CONTENT
        )
        val selectableItemBackgroundResource = android.R.attr.selectableItemBackground
        val typedValue = TypedValue()
        if (instance.theme.resolveAttribute(selectableItemBackgroundResource, typedValue, true)) {
            tr.setBackgroundResource(typedValue.resourceId)
        } else {
            tr.setBackgroundResource(android.R.drawable.list_selector_background)
        }

        val padding = (StringUtils.scaledSize(7.5F, instance) * instance.resources.displayMetrics.density).roundToInt()
        tr.setPadding(0, padding, 0, padding)

        val routeTextView = TextView(instance)
        tr.addView(routeTextView)
        val routeNumber = route.optJSONObject("route").optString("route")
        routeTextView.text = routeNumber
        routeTextView.setTextColor(color)
        routeTextView.setTextSize(TypedValue.COMPLEX_UNIT_SP, StringUtils.scaledSize(20F, instance))
        val routeTextLayoutParams: ViewGroup.LayoutParams = routeTextView.layoutParams
        routeTextLayoutParams.width =
            (StringUtils.scaledSize(51F, instance) * instance.resources.displayMetrics.density).roundToInt()
        routeTextView.layoutParams = routeTextLayoutParams
        val destTextView = TextView(instance)
        tr.addView(destTextView);

        destTextView.isSingleLine = true
        destTextView.ellipsize = TextUtils.TruncateAt.MARQUEE
        destTextView.marqueeRepeatLimit = -1
        destTextView.isFocusable = true
        destTextView.isFocusableInTouchMode = true
        destTextView.setHorizontallyScrolling(true)
        destTextView.isSelected = true
        val destTextLayoutParams: ViewGroup.LayoutParams = destTextView.layoutParams
        destTextLayoutParams.width =
            (StringUtils.scaledSize(95F, instance) * instance.resources.displayMetrics.density).roundToInt()
        destTextView.layoutParams = destTextLayoutParams

        var dest = route.optJSONObject("route").optJSONObject("dest").optString(Shared.language)
        if (Shared.language == "en") {
            dest = StringUtils.capitalize(dest)
        }
        dest = (if (Shared.language == "en") "To " else "往").plus(dest)
        destTextView.text = dest
        destTextView.setTextColor(color)
        destTextView.setTextSize(TypedValue.COMPLEX_UNIT_SP, StringUtils.scaledSize(15F, instance))
        table.addView(tr)

        val baseline = View(instance)
        baseline.layoutParams = TableRow.LayoutParams(TableRow.LayoutParams.MATCH_PARENT, 1)
        baseline.setBackgroundColor(Color(0xFF333333).toArgb())
        table.addView(baseline)

        tr.setOnClickListener {
            val intent = Intent(instance, ListStopsActivity::class.java)
            intent.putExtra("route", route.toString())
            instance.startActivity(intent)
        }
        tr.setOnLongClickListener {
            haptic.performHapticFeedback(HapticFeedbackType.LongPress)
            instance.runOnUiThread {
                val text = routeNumber.plus(" ").plus(dest).plus("\n(").plus(if (Shared.language == "en") {
                    when (route.optString("co")) {
                        "kmb" -> "KMB"
                        "ctb" -> "CTB"
                        "nlb" -> "NLB"
                        "mtr-bus" -> "MTR-Bus"
                        "gmb" -> "GMB"
                        else -> "???"
                    }
                } else {
                    when (route.optString("co")) {
                        "kmb" -> "九巴"
                        "ctb" -> "城巴"
                        "nlb" -> "嶼巴"
                        "mtr-bus" -> "港鐵巴士"
                        "gmb" -> "專線小巴"
                        else -> "???"
                    }
                }).plus(")")
                Toast.makeText(instance, text, Toast.LENGTH_LONG).show()
            }
            return@setOnLongClickListener true
        }
    }
    val scrollView: ScrollView = instance.findViewById(R.id.route_list_scroll)
    scrollView.requestFocus()
}