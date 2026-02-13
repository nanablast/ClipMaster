# Contributing to ClipMaster

感谢你愿意参与 ClipMaster。

## 先做什么

1. 先搜索已有 Issue，避免重复。
2. 如果是新功能，先开 Issue 说明目标与方案。
3. 对于较大改动，建议先讨论再开始实现。

## 本地开发

```bash
swift build
swift test
```

Release 构建与部署：

```bash
bash build.sh
bash deploy.sh
```

## 提交建议

- 变更保持小而聚焦，避免“顺手大改”。
- 保持现有代码风格与命名习惯。
- 有行为变化时，补充或更新测试。
- 提交信息建议使用简短动词开头，例如：
  - `fix: ...`
  - `feat: ...`
  - `refactor: ...`
  - `test: ...`
  - `docs: ...`

## Pull Request 检查清单

- [ ] 本地 `swift test` 通过
- [ ] 变更范围清晰、无无关修改
- [ ] 必要文档已更新（README/CHANGELOG）
- [ ] 涉及权限/快捷键改动时，已说明验证步骤

## 报告 Bug

请尽量提供：

- macOS 版本
- ClipMaster 版本（或 commit）
- 复现步骤
- 预期行为与实际行为
- 相关日志（可脱敏）

