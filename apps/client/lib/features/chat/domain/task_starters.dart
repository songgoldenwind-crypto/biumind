import 'package:flutter/material.dart';

import '../../../app/theme/category_colors.dart';
import 'greeting.dart';

/// 任务首页起点：办公交付，不是聊天破冰。
const kTaskStarters = <StarterPrompt>[
  StarterPrompt(
    icon: Icons.newspaper_outlined,
    title: '纪要变周报',
    prompt: '把这份纪要整理成周报，写到工作目录里的 markdown 文件，开头用本周结论。',
    tone: StarterPromptTones.summarize,
    kind: 'office',
  ),
  StarterPrompt(
    icon: Icons.slideshow_outlined,
    title: '做成幻灯片提纲',
    prompt: '根据下面材料写一份幻灯片提纲，保存为 slides.md，每页一行标题加三条要点。',
    tone: StarterPromptTones.writing,
    kind: 'office',
  ),
  StarterPrompt(
    icon: Icons.table_chart_outlined,
    title: '整理成表格',
    prompt: '把下面信息整理成 CSV 表格并写到工作目录，第一行做表头。',
    tone: StarterPromptTones.code,
    kind: 'office',
  ),
  StarterPrompt(
    icon: Icons.science_outlined,
    title: '写研究简报',
    prompt: '针对这个问题写一份研究简报，必须包含：问题、发现、证据、结论、待办。保存为 markdown。',
    tone: StarterPromptTones.concept,
    kind: 'office',
  ),
];
