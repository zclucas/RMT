#pragma once
#include <stdexcept>
// SearchAll owns a single screen/window snapshot and returns an opaque result handle.
// The caller must release it even when copying the points is interrupted.
namespace rmt_search_all {
struct Result { std::vector<cv::Point> points; };
struct Hit { cv::Rect box; double score; };

inline cv::Mat readImage(const wchar_t* path) {
    FILE* file = nullptr;
    if (_wfopen_s(&file, path, L"rb") || !file) return {};
    std::unique_ptr<FILE, decltype(&fclose)> owner(file, fclose);
    if (fseek(file, 0, SEEK_END) != 0) return {};
    long size = ftell(file);
    if (size <= 0 || fseek(file, 0, SEEK_SET) != 0) return {};
    std::vector<uchar> bytes(static_cast<size_t>(size));
    if (fread(bytes.data(), 1, bytes.size(), file) != bytes.size()) return {};
    return cv::imdecode(bytes, cv::IMREAD_UNCHANGED);
}

inline cv::Mat channels(const cv::Mat& src, bool color) {
    cv::Mat dst;
    if (color) {
        if (src.channels() == 4) cv::cvtColor(src, dst, cv::COLOR_BGRA2BGR);
        else if (src.channels() == 1) cv::cvtColor(src, dst, cv::COLOR_GRAY2BGR);
        else dst = src;
    } else {
        if (src.channels() == 4) cv::cvtColor(src, dst, cv::COLOR_BGRA2GRAY);
        else if (src.channels() == 3) cv::cvtColor(src, dst, cv::COLOR_BGR2GRAY);
        else dst = src;
    }
    return dst;
}

inline cv::Mat edges(const cv::Mat& gray) {
    cv::Mat smooth, gx, gy, ax, ay, result;
    cv::GaussianBlur(gray, smooth, cv::Size(3, 3), 0);
    cv::Sobel(smooth, gx, CV_16S, 1, 0, 3);
    cv::Sobel(smooth, gy, CV_16S, 0, 1, 3);
    cv::convertScaleAbs(gx, ax);
    cv::convertScaleAbs(gy, ay);
    cv::addWeighted(ax, .5, ay, .5, 0, result);
    return result;
}

inline std::vector<cv::Point> images(const cv::Mat& shot, const cv::Mat& original,
    int threshold, bool color, bool adaptive, bool topLeft = false) {
    cv::Mat image = channels(shot, color), templ = channels(original, color), alpha;
    if (original.channels() == 4) {
        cv::extractChannel(original, alpha, 3);
        cv::threshold(alpha, alpha, 0, 255, cv::THRESH_BINARY);
        if (!cv::countNonZero(alpha)) throw std::runtime_error("empty alpha mask");
        if (cv::countNonZero(alpha) == alpha.rows * alpha.cols) alpha.release();
    }
    std::vector<double> scales{1.0};
    if (adaptive) {
        const double ladder[] = {1.25, .8, 1.5, .6667, 1.75, .5714, 2., .5};
        for (double s : ladder) {
            scales.push_back(s);
            for (int d = -3; d <= 3; ++d) if (d) scales.push_back(s * (1. + d * .02));
        }
    }
    // Keep the existing adaptive grayscale tolerance for re-rasterized text:
    // scaled weak matches require matching edges; transparent pixels are excluded.
    cv::Mat imageEdges, templateEdges;
    if (adaptive && !color) {
        imageEdges = edges(image);
        templateEdges = edges(templ);
        if (!alpha.empty()) cv::bitwise_and(templateEdges, templateEdges, templateEdges, alpha);
    }
    std::vector<Hit> hits;
    for (double scale : scales) {
        cv::Size size(std::max(1, cvRound(templ.cols * scale)), std::max(1, cvRound(templ.rows * scale)));
        if (size.width > image.cols || size.height > image.rows) continue;
        cv::Mat target, mask, scores;
        cv::resize(templ, target, size, 0, 0, scale < 1 ? cv::INTER_AREA : cv::INTER_LINEAR);
        if (!alpha.empty()) cv::resize(alpha, mask, size, 0, 0, cv::INTER_NEAREST);
        cv::Scalar mean, deviation;
        cv::meanStdDev(target, mean, deviation, mask);
        bool constant = cv::sum(deviation)[0] < 1e-6;
        int method = constant ? cv::TM_SQDIFF : mask.empty() ? cv::TM_CCOEFF_NORMED : cv::TM_CCORR_NORMED;
        cv::matchTemplate(image, target, scores, method, mask);
        double norm = (mask.empty() ? target.total() : cv::countNonZero(mask)) * target.channels() * 255.0 * 255.0;
        for (int y = 0; y < scores.rows; ++y) {
            float* row = scores.ptr<float>(y);
            for (int x = 0; x < scores.cols; ++x)
                row[x] = std::isfinite(row[x]) ? (constant ? static_cast<float>(1.0 - std::sqrt(std::max(0.f, row[x]) / norm)) : row[x]) : -1.f;
        }
        bool relaxed = adaptive && !color && !constant && std::abs(scale - 1.) >= .005;
        cv::Mat edgeScores;
        if (relaxed) {
            cv::Mat targetEdges;
            cv::resize(templateEdges, targetEdges, size, 0, 0, scale < 1 ? cv::INTER_AREA : cv::INTER_LINEAR);
            cv::matchTemplate(imageEdges, targetEdges, edgeScores, cv::TM_CCOEFF_NORMED);
            cv::patchNaNs(edgeScores, -1);
        }
        while (true) {
            double best;
            cv::Point pos;
            cv::minMaxLoc(scores, nullptr, &best, nullptr, &pos);
            double required = threshold / 100.0;
            if (best + 1e-6 < required - (relaxed ? .12 : 0.) || best < 0) break;
            bool accepted = best + 1e-6 >= required;
            if (!accepted && relaxed) {
                cv::Rect vicinity(std::max(0, pos.x - 4), std::max(0, pos.y - 4), 1, 1);
                vicinity.width = std::min(edgeScores.cols, pos.x + 5) - vicinity.x;
                vicinity.height = std::min(edgeScores.rows, pos.y + 5) - vicinity.y;
                double edgeBest;
                cv::minMaxLoc(edgeScores(vicinity), nullptr, &edgeBest);
                accepted = std::isfinite(edgeBest) && edgeBest >= .55;
            }
            if (accepted && adaptive && !color && !mask.empty()) {
                cv::Mat diff;
                cv::absdiff(image(cv::Rect(pos, size)), target, diff);
                double tolerance = std::max(12., (100 - threshold) * 3.);
                if (best < required) tolerance *= 2;
                accepted = cv::mean(diff, mask)[0] <= tolerance;
            }
            if (accepted) hits.push_back({cv::Rect(pos, size), best});
            // Local peak suppression: one response per target instead of neighboring pixels.
            int dx = std::max(1, size.width / 2), dy = std::max(1, size.height / 2);
            cv::Rect suppress(std::max(0, pos.x - dx), std::max(0, pos.y - dy), 1, 1);
            suppress.width = std::min(scores.cols, pos.x + dx + 1) - suppress.x;
            suppress.height = std::min(scores.rows, pos.y + dy + 1) - suppress.y;
            scores(suppress).setTo(-1);
        }
    }
    std::stable_sort(hits.begin(), hits.end(), [](const Hit& a, const Hit& b) { return a.score > b.score; });
    std::vector<cv::Rect> accepted;
    std::vector<cv::Point> points;
    for (const auto& hit : hits) {
        bool duplicate = false;
        for (const auto& box : accepted) {
            double intersection = (box & hit.box).area();
            if (intersection / (box.area() + hit.box.area() - intersection) > .3) { duplicate = true; break; }
        }
        if (!duplicate) {
            accepted.push_back(hit.box);
            points.emplace_back(hit.box.x + (topLeft ? 0 : hit.box.width / 2), hit.box.y + (topLeft ? 0 : hit.box.height / 2));
        }
    }
    return points;
}

inline std::vector<cv::Point> colors(const cv::Mat& shot, unsigned int color, int threshold) {
    cv::Mat image = channels(shot, true), mask;
    int b = color & 255, g = (color >> 8) & 255, r = (color >> 16) & 255;
    int tolerance = static_cast<int>((100 - threshold) * 2.55);
    cv::inRange(image, cv::Scalar(std::max(0, b - tolerance), std::max(0, g - tolerance), std::max(0, r - tolerance)),
        cv::Scalar(std::min(255, b + tolerance), std::min(255, g + tolerance), std::min(255, r + tolerance)), mask);
    std::vector<cv::Point> points;
    cv::findNonZero(mask, points);
    return points;
}
}

cv::Mat captureScreen(int x, int y, int width, int height);
cv::Mat captureScreen(int hwnd, int x, int y, int width, int height);

extern "C" IMAGEFINDER_API void* __cdecl SearchAllCapture(const wchar_t* path,
    int x, int y, int width, int height, int threshold, int colorMatch, int adaptive, int colorMode, unsigned int color, int hwnd) {
    if (width <= 0 || height <= 0 || threshold < 0 || threshold > 100) return nullptr;
    try {
        cv::Mat image = hwnd ? captureScreen(hwnd, x, y, width, height) : captureScreen(x, y, width, height);
        if (image.empty()) return nullptr;
        auto result = std::make_unique<rmt_search_all::Result>();
        if (colorMode) result->points = rmt_search_all::colors(image, color, threshold);
        else {
            if (!path || !*path) return nullptr;
            cv::Mat templ = rmt_search_all::readImage(path);
            if (templ.empty()) return nullptr;
            result->points = rmt_search_all::images(image, templ, threshold, colorMatch != 0, adaptive != 0);
        }
        for (auto& point : result->points) { point.x += x; point.y += y; }
        return result.release();
    } catch (...) { return nullptr; }
}
extern "C" IMAGEFINDER_API int __cdecl SearchAllCount(void* handle) {
    return handle ? static_cast<int>(static_cast<rmt_search_all::Result*>(handle)->points.size()) : 0;
}
extern "C" IMAGEFINDER_API const void* __cdecl SearchAllPoints(void* handle) {
    return handle ? static_cast<rmt_search_all::Result*>(handle)->points.data() : nullptr;
}
extern "C" IMAGEFINDER_API void __cdecl SearchAllRelease(void* handle) {
    delete static_cast<rmt_search_all::Result*>(handle);
}
