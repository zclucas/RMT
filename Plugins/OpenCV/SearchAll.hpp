#pragma once
#include <cstdint>
#include <stdexcept>
#include <unordered_map>
// SearchAll owns a single screen/window snapshot and returns an opaque result handle.
// The caller must release it even when copying the points is interrupted.
namespace rmt_search_all {
struct Result { std::vector<cv::Point> points; };
struct Hit { cv::Rect box; double score; };

inline bool scanBefore(cv::Point a, cv::Point b) {
    return a.y != b.y ? a.y < b.y : a.x < b.x;
}

inline std::uint64_t hitCell(int x, int y) {
    return (static_cast<std::uint64_t>(y) << 32) | static_cast<std::uint32_t>(x);
}

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
    int threshold, bool color, bool adaptive, bool firstOnly = false) {
    cv::Mat image = channels(shot, color), templ = channels(original, color), alpha;
    if (original.channels() == 4) {
        cv::extractChannel(original, alpha, 3);
        cv::threshold(alpha, alpha, 0, 255, cv::THRESH_BINARY);
        const int visiblePixels = cv::countNonZero(alpha);
        if (!visiblePixels) {
            if (firstOnly) return {};
            throw std::runtime_error("empty alpha mask");
        }
        if (visiblePixels == alpha.total()) alpha.release();
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
        const bool relaxed = adaptive && !color && !constant && std::abs(scale - 1.) >= .005;
        const double required = threshold / 100.0;
        std::vector<cv::Point> candidates;
        float highest = -1;
        for (int y = 0; y < scores.rows; ++y) {
            float* row = scores.ptr<float>(y);
            for (int x = 0; x < scores.cols; ++x) {
                float& score = row[x];
                if (!std::isfinite(score)) continue;
                if (constant)
                    score = static_cast<float>(1.0 - std::sqrt(std::max(0.f, score) / norm));
                if (score >= 0 && score + 1e-6 >= required - (relaxed ? .12 : 0.)) {
                    candidates.emplace_back(x, y);
                    highest = std::max(highest, score);
                }
            }
        }
        if (candidates.empty()) continue;
        const bool firstAtOriginalSize = firstOnly && scale == 1.0;
        const cv::Point firstCandidate = candidates.front();
        if (firstAtOriginalSize && (color || !adaptive || mask.empty())
            && scores.at<float>(firstCandidate) == highest)
            return {firstCandidate};

        // Visit peaks in the same order as repeated minMaxLoc, without scanning
        // the whole score map again after suppressing each one.
        std::sort(candidates.begin(), candidates.end(), [&](cv::Point a, cv::Point b) {
            const float sa = scores.at<float>(a), sb = scores.at<float>(b);
            return sa != sb ? sa > sb : scanBefore(a, b);
        });
        cv::Mat edgeScores;
        if (relaxed) {
            if (imageEdges.empty()) {
                imageEdges = edges(image);
                templateEdges = edges(templ);
                if (!alpha.empty()) cv::bitwise_and(templateEdges, templateEdges, templateEdges, alpha);
            }
            cv::Mat targetEdges;
            cv::resize(templateEdges, targetEdges, size, 0, 0, scale < 1 ? cv::INTER_AREA : cv::INTER_LINEAR);
            cv::matchTemplate(imageEdges, targetEdges, edgeScores, cv::TM_CCOEFF_NORMED);
            cv::patchNaNs(edgeScores, -1);
        }
        for (cv::Point pos : candidates) {
            const double best = scores.at<float>(pos);
            if (best < 0) continue;
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
            if (accepted) {
                // This point wins both by score and by position, so no other
                // fixed-size candidate can replace or suppress it.
                if (firstAtOriginalSize && pos == firstCandidate && hits.empty())
                    return {pos};
                hits.push_back({cv::Rect(pos, size), best});
            }
            // Local peak suppression: one response per target instead of neighboring pixels.
            int dx = std::max(1, size.width / 2), dy = std::max(1, size.height / 2);
            cv::Rect suppress(std::max(0, pos.x - dx), std::max(0, pos.y - dy), 1, 1);
            suppress.width = std::min(scores.cols, pos.x + dx + 1) - suppress.x;
            suppress.height = std::min(scores.rows, pos.y + dy + 1) - suppress.y;
            scores(suppress).setTo(-1);
        }
        if (firstAtOriginalSize && !hits.empty()) break;
    }
    std::stable_sort(hits.begin(), hits.end(), [](const Hit& a, const Hit& b) { return a.score > b.score; });
    // Boxes with a nonzero overlap have origins in the same or neighboring cells.
    cv::Size cellSize(1, 1);
    for (const auto& hit : hits) {
        cellSize.width = std::max(cellSize.width, hit.box.width);
        cellSize.height = std::max(cellSize.height, hit.box.height);
    }
    std::unordered_map<std::uint64_t, std::vector<cv::Rect>> accepted;
    std::vector<cv::Point> points;
    for (const auto& hit : hits) {
        const int cx = hit.box.x / cellSize.width, cy = hit.box.y / cellSize.height;
        bool duplicate = false;
        for (int y = std::max(0, cy - 1); y <= cy + 1 && !duplicate; ++y) {
            for (int x = std::max(0, cx - 1); x <= cx + 1 && !duplicate; ++x) {
                const auto cell = accepted.find(hitCell(x, y));
                if (cell == accepted.end()) continue;
                for (const auto& box : cell->second) {
                    double intersection = (box & hit.box).area();
                    if (intersection / (box.area() + hit.box.area() - intersection) > .3) {
                        duplicate = true;
                        break;
                    }
                }
            }
        }
        if (duplicate) continue;
        accepted[hitCell(cx, cy)].push_back(hit.box);
        if (!firstOnly)
            points.emplace_back(hit.box.x + hit.box.width / 2, hit.box.y + hit.box.height / 2);
        else if (points.empty())
            points.push_back(hit.box.tl());
        else if (scanBefore(hit.box.tl(), points.front()))
            points.front() = hit.box.tl();
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
