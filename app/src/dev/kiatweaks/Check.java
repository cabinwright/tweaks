package dev.kiatweaks;

import android.content.Context;
import android.graphics.Canvas;
import android.graphics.Paint;
import android.graphics.Path;
import android.graphics.RectF;
import android.view.View;

import dev.kiamenu.api.ui.KiaPage;

/**
 * Kia's list checkbox (Setup > General > Date & Time): a rounded teal square with a check
 * cut out in the page colour, an outlined square when off. Colours measured from the stock
 * screen in each mode.
 */
final class Check extends View {
    private final Paint paint = new Paint(Paint.ANTI_ALIAS_FLAG);
    private final Path mark = new Path();
    private final RectF box = new RectF();
    private final int fill;
    private final int cut;
    private final int edge;
    private final int empty;
    private boolean checked;

    Check(Context context, int emptyColor) {
        super(context);
        boolean night = KiaPage.isNight(context);
        fill = night ? 0xFF176972 : 0xFF40CABE;
        cut = night ? 0xFF161618 : 0xFFFFFFFF;
        edge = night ? 0xFF4A4F55 : 0xFFB0B4B6;
        empty = emptyColor;
    }

    void setChecked(boolean on) {
        if (on != checked) {
            checked = on;
            invalidate();
        }
    }

    @Override
    protected void onDraw(Canvas c) {
        float w = getWidth(), h = getHeight();
        float s = Math.min(w, h);
        float stroke = Math.max(2f, s / 14f);
        box.set((w - s) / 2 + stroke / 2, (h - s) / 2 + stroke / 2, (w + s) / 2 - stroke / 2, (h + s) / 2 - stroke / 2);
        float r = s * 0.16f;
        paint.setStyle(Paint.Style.FILL);
        paint.setColor(checked ? fill : empty);
        c.drawRoundRect(box, r, r, paint);
        if (!checked) {
            paint.setStyle(Paint.Style.STROKE);
            paint.setStrokeWidth(stroke);
            paint.setColor(edge);
            c.drawRoundRect(box, r, r, paint);
            return;
        }
        float x = box.left, y = box.top, b = box.width();
        mark.reset();
        mark.moveTo(x + b * 0.24f, y + b * 0.50f);
        mark.lineTo(x + b * 0.43f, y + b * 0.69f);
        mark.lineTo(x + b * 0.77f, y + b * 0.31f);
        paint.setStyle(Paint.Style.STROKE);
        paint.setStrokeWidth(b * 0.12f);
        paint.setStrokeCap(Paint.Cap.ROUND);
        paint.setStrokeJoin(Paint.Join.ROUND);
        paint.setColor(cut);
        c.drawPath(mark, paint);
    }
}
