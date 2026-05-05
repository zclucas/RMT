#Requires AutoHotkey v2.0

class HumanMouse {
    static Instance := ""
    static Pi := 3.141592653589793

    __New() {
        this.IsEnabled := false
        this.Intensity := 50
        this.CurveType := "bezier"
        this.Deviation := 50
        this.JitterAmount := 1.5
        this.OvershootRate := 0.15
        this.OvershootDist := 5
        this.Speed := 80
        this.Easing := "easeInOut"
        this.SamplePoints := 50
    }

    static GetInstance() {
        if (HumanMouse.Instance == "")
            HumanMouse.Instance := HumanMouse()
        return HumanMouse.Instance
    }

    Move(targetX, targetY, speed := "") {
        if (!this.IsEnabled) {
            MouseMove(targetX, targetY, speed)
            return
        }

        if (speed != "")
            this.Speed := speed

        CoordMode("Mouse", "Screen")
        MouseGetPos(&startX, &startY)

        distance := Sqrt((targetX - startX) ** 2 + (targetY - startY) ** 2)
        this.AutoCalculateParams(distance)

        path := this.GeneratePath(startX, startY, targetX, targetY)
        this.ExecutePath(path)
    }

    AutoCalculateParams(distance) {
        intensity := this.Intensity

        distFactor := 1.0
        if (distance < 100)
            distFactor := 0.5 + (distance / 100) * 0.5
        else if (distance < 300)
            distFactor := 0.8 + ((distance - 100) / 200) * 0.2
        else if (distance > 800)
            distFactor := Min(1.3, 1.0 + (distance - 800) / 1000)

        speedFactor := this.Speed / 100

        baseDeviation := 20 + intensity * 1.3
        this.Deviation := Round(baseDeviation * distFactor)

        baseJitter := 0.3 + intensity * 0.037
        this.JitterAmount := Round(baseJitter * (1.5 - speedFactor * 0.5), 1)

        this.OvershootRate := (intensity / 100) * 0.3 * (1.2 - speedFactor * 0.2)
        this.OvershootDist := 2 + intensity * 0.08
    }

    GeneratePath(x1, y1, x2, y2) {
        path := []

        dist := Sqrt((x2 - x1) ** 2 + (y2 - y1) ** 2)

        if (dist < 80)
            numPoints := Max(6, Round(dist / 10))
        else if (dist < 200)
            numPoints := Max(10, Round(dist / 15))
        else if (dist < 500)
            numPoints := Max(15, Round(dist / 20))
        else
            numPoints := Max(20, Min(this.SamplePoints, Round(dist / 25)))

        ctrlPoints := this.GenerateControlPoints(x1, y1, x2, y2)

        loop numPoints {
            t := (A_Index - 1) / (numPoints - 1)
            easedT := this.ApplyEasing(t)

            point := this.BezierPoint(ctrlPoints, easedT)
            point := this.AddJitter(point.X, point.Y, t)

            if (this.OvershootRate > 0 && Random() < this.OvershootRate) {
                point := this.ApplyOvershoot(point.X, point.Y, x2, y2, t)
            }

            path.Push({ X: point.X, Y: point.Y })
        }

        return path
    }

    GenerateControlPoints(x1, y1, x2, y2) {
        midX := (x1 + x2) / 2
        midY := (y1 + y2) / 2

        dx := x2 - x1
        dy := y2 - y1

        perpX := -dy
        perpY := dx
        len := Sqrt(perpX ** 2 + perpY ** 2)
        if (len > 0) {
            perpX /= len
            perpY /= len
        }

        offset1 := (Random() - 0.5) * 2 * this.Deviation
        offset2 := (Random() - 0.5) * 2 * this.Deviation

        cp1x := midX + perpX * offset1 - dx * 0.2
        cp1y := midY + perpY * offset1 - dy * 0.2
        cp2x := midX + perpX * offset2 + dx * 0.2
        cp2y := midY + perpY * offset2 + dy * 0.2

        return [
            { X: x1, Y: y1 },
            { X: cp1x, Y: cp1y },
            { X: cp2x, Y: cp2y },
            { X: x2, Y: y2 }
        ]
    }

    BezierPoint(ctrlPoints, t) {
        p0 := ctrlPoints[1]
        p1 := ctrlPoints[2]
        p2 := ctrlPoints[3]
        p3 := ctrlPoints[4]

        u := 1 - t
        tt := t * t
        uu := u * u
        uuu := uu * u
        ttt := tt * t

        x := uuu * p0.X
        x += 3 * uu * t * p1.X
        x += 3 * u * tt * p2.X
        x += ttt * p3.X

        y := uuu * p0.Y
        y += 3 * uu * t * p1.Y
        y += 3 * u * tt * p2.Y
        y += ttt * p3.Y

        return { X: x, Y: y }
    }

    ApplyEasing(t) {
        switch this.Easing {
            case "linear":
                return t
            case "easeIn":
                return t * t
            case "easeOut":
                return t * (2 - t)
            case "easeInOut":
                return t < 0.5 ? 2 * t * t : -1 + (4 - 2 * t) * t
            case "easeInCubic":
                return t * t * t
            case "easeOutCubic":
                t -= 1
                return t * t * t + 1
            case "easeInOutCubic":
                t *= 2
                if (t < 1)
                    return 0.5 * t * t * t
                t -= 2
                return 0.5 * (t * t * t + 2)
            default:
                return t < 0.5 ? 2 * t * t : -1 + (4 - 2 * t) * t
        }
    }

    AddJitter(x, y, t) {
        if (this.JitterAmount <= 0)
            return { X: x, Y: y }

        edgeFactor := 1 - Abs(2 * t - 1) ** 2
        jitterX := (Random() - 0.5) * 2 * this.JitterAmount * edgeFactor
        jitterY := (Random() - 0.5) * 2 * this.JitterAmount * edgeFactor

        return { X: x + jitterX, Y: y + jitterY }
    }

    ApplyOvershoot(x, y, targetX, targetY, t) {
        if (t > 0.8) {
            overshootT := (t - 0.8) / 0.2
            dx := targetX - x
            dy := targetY - y
            dist := Sqrt(dx ** 2 + dy ** 2)
            if (dist > 0) {
                overshootAmount := Sin(overshootT * HumanMouse.Pi) * this.OvershootDist * (1 - overshootT)
                x += (dx / dist) * overshootAmount
                y += (dy / dist) * overshootAmount
            }
        }
        return { X: x, Y: y }
    }

    ExecutePath(path) {
        if (path.Length < 2)
            return

        totalDist := 0
        loop path.Length - 1 {
            current := path[A_Index]
            next := path[A_Index + 1]
            dx := next.X - current.X
            dy := next.Y - current.Y
            totalDist += Sqrt(dx ** 2 + dy ** 2)
        }

        minDuration := 60
        maxDuration := 500
        duration := minDuration + (maxDuration - minDuration) * (100 - this.Speed) / 100

        duration := Max(minDuration, duration * (0.8 + this.Intensity / 250))

        baseDelay := Max(1, Round(duration / path.Length))

        loop path.Length - 1 {
            current := path[A_Index]
            MouseMove(Round(current.X), Round(current.Y), 0)
            Sleep(baseDelay)
        }

        lastPoint := path[path.Length]
        MouseMove(Round(lastPoint.X), Round(lastPoint.Y), 0)
    }

    SetParams(params) {
        if (params.HasProp("IsEnabled"))
            this.IsEnabled := params.IsEnabled
        if (params.HasProp("Intensity"))
            this.Intensity := params.Intensity
        if (params.HasProp("CurveType"))
            this.CurveType := params.CurveType
        if (params.HasProp("Deviation"))
            this.Deviation := params.Deviation
        if (params.HasProp("JitterAmount"))
            this.JitterAmount := params.JitterAmount
        if (params.HasProp("OvershootRate"))
            this.OvershootRate := params.OvershootRate
        if (params.HasProp("OvershootDist"))
            this.OvershootDist := params.OvershootDist
        if (params.HasProp("Speed"))
            this.Speed := params.Speed
        if (params.HasProp("Easing"))
            this.Easing := params.Easing
        if (params.HasProp("SamplePoints"))
            this.SamplePoints := params.SamplePoints
    }
}
