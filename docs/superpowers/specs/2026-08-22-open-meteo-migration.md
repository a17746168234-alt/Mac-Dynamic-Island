# Mac灵动岛无密钥天气设计

## 目标

- 将天气源从和风天气替换为无需 API Key 的 Open-Meteo。
- 修复定位已授权后仍被和风天气凭据前置条件拦住的问题。
- 删除天气设置中的 API Host、API Key 与凭据管理界面。
- 删除本机钥匙串中旧的和风天气 Host 和 API Key，不读取或记录其内容。
- 保持现有天气卡片尺寸、主页布局和其他功能不变。

## 已确认方案

- 使用 `https://api.open-meteo.com/v1/forecast` 的默认 Best Match 模型。
- 传入 Core Location 提供的当前位置坐标，请求实时温度、湿度、天气代码与昼夜状态。
- 使用系统反向地理编码显示中文地区名；失败时显示“当前位置”，不影响天气数据。
- 将 WMO 天气代码映射为中文天气文字和 SF Symbols。
- 缓存继续保持 30 分钟；请求失败时保留最后一次成功数据并显示简短错误。
- 卡片底部显示可点击的“Open-Meteo”来源标注。
- Open-Meteo 免费接口仅用于用户确认的个人非商业场景。

## 验收标准

- 不配置任何 Host 或 Key 即可请求天气。
- macOS 的 `.authorizedAlways` 状态会直接发起定位并刷新天气，不再等待凭据。
- 设置页不再出现和风天气、API Host、API Key 或清除凭据按钮。
- 请求只发送到 `api.open-meteo.com`，且不含授权请求头。
- 旧钥匙串账户 `qweather-api-host`、`qweather-api-key` 被删除。
- 核心测试、Debug 构建与 Release 构建通过，并安装打开新版本。
