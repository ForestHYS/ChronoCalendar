from django.shortcuts import get_object_or_404
from django.conf import settings
from django.utils import timezone
from rest_framework.permissions import IsAuthenticated
from rest_framework.views import APIView

from tasks.views import err, ok

from .graph import build_graph
from .history import prepare_conversation_context
from .plan_interaction import (
    get_active_plan_state,
    handle_plan_interaction,
    handle_plan_text_message,
)
from .models import AgentMessage, AgentSession, ApprovalRequest, UserLlmConfig
from .serializers import (
    AgentMessageInSerializer,
    AgentMessageOutSerializer,
    AgentSessionSerializer,
    UserLlmConfigInSerializer,
)
from .registry import run_skill
from .llm import test_llm_connection


_graph = None


def _get_graph():
    global _graph
    if _graph is None:
        _graph = build_graph()
    return _graph


class AgentSessionCreateView(APIView):
    permission_classes = [IsAuthenticated]

    def get(self, request):
        sessions = AgentSession.objects.filter(user=request.user)[:20]
        return ok(AgentSessionSerializer(sessions, many=True).data)

    def post(self, request):
        s = AgentSession.objects.create(user=request.user)
        return ok(AgentSessionSerializer(s).data)


class AgentMessageCreateView(APIView):
    permission_classes = [IsAuthenticated]

    def get(self, request, session_id):
        session = get_object_or_404(AgentSession, pk=session_id, user=request.user)
        msgs = session.messages.all()
        return ok(AgentMessageOutSerializer(msgs, many=True).data)

    def post(self, request, session_id):
        session = get_object_or_404(AgentSession, pk=session_id, user=request.user)
        ins = AgentMessageInSerializer(data=request.data)
        if not ins.is_valid():
            return err("VALIDATION_ERROR", "输入数据无效", ins.errors)

        text = ins.validated_data["text"]
        client_context = ins.validated_data.get("client_context") or {}
        interaction = ins.validated_data.get("interaction")

        history_summary, chat_history = prepare_conversation_context(session)

        try:
            if isinstance(interaction, dict) and interaction.get("type"):
                resp = handle_plan_interaction(
                    session=session,
                    interaction=interaction,
                    client_context=client_context,
                )
            else:
                active_plan = get_active_plan_state(session, for_text_intercept=True)

                def _run_graph() -> dict:
                    graph = _get_graph()
                    state = {
                        "user_id": str(request.user.id),
                        "session_id": str(session.id),
                        "input_text": text,
                        "client_context": client_context,
                        "chat_history": chat_history,
                        "history_summary": history_summary or "",
                    }
                    out = graph.invoke(state)
                    result = out.get("response") if isinstance(out, dict) else None
                    if not isinstance(result, dict):
                        return {"type": "message", "text": "系统繁忙，请稍后重试。"}
                    return result

                if active_plan:
                    plan_resp = handle_plan_text_message(
                        session=session,
                        user_text=text,
                        active_plan=active_plan,
                        chat_history=chat_history,
                        client_context=client_context,
                        run_general_agent=_run_graph,
                    )
                    if plan_resp is not None:
                        resp = plan_resp
                    else:
                        resp = _run_graph()
                else:
                    resp = _run_graph()
        except Exception:
            # Agent 不应因 LLM/解析失败导致 500；统一降级为可读提示
            resp = {
                "type": "message",
                "text": "AI 解析暂时不可用（可能是 LLM 配置无效）。你也可以直接用任务编辑页创建，或稍后再试。",
            }

        AgentMessage.objects.create(session=session, role=AgentMessage.Role.USER, content_text=text)

        assistant_msg = AgentMessage.objects.create(
            session=session,
            role=AgentMessage.Role.ASSISTANT,
            content_text=resp.get("text") or resp.get("message") or "",
            content_json=resp,
        )
        session.save(update_fields=["updated_at"])

        return ok({
            "response": resp,
            "assistant_message_id": str(assistant_msg.id),
        })


class ApprovalDetailView(APIView):
    permission_classes = [IsAuthenticated]

    def get(self, request, approval_id):
        ar = get_object_or_404(ApprovalRequest, pk=approval_id, user=request.user)
        return ok(
            {
                "id": str(ar.id),
                "status": ar.status,
                "skill_name": ar.skill_name,
                "args_json": ar.args_json,
                "summary": ar.summary,
                "created_at": ar.created_at.isoformat(),
                "decided_at": ar.decided_at.isoformat() if ar.decided_at else None,
            }
        )


class ApprovalApproveView(APIView):
    permission_classes = [IsAuthenticated]

    def post(self, request, approval_id):
        ar = get_object_or_404(
            ApprovalRequest, pk=approval_id, user=request.user, status=ApprovalRequest.Status.PENDING
        )
        if ar.skill_name == "delete_task":
            out = run_skill("delete_task", str(request.user.id), ar.args_json)
            if not out.get("ok"):
                return err("EXEC_FAILED", out.get("error", "执行失败"))
            ar.status = ApprovalRequest.Status.APPROVED
            ar.decided_at = timezone.now()
            ar.save(update_fields=["status", "decided_at"])
            title = out.get("title", "")
            return ok(
                {
                    "response": {
                        "type": "message",
                        "text": f"已删除任务：{title}",
                    }
                }
            )
        return err("UNSUPPORTED", "该审批类型暂不支持执行")


class ApprovalRejectView(APIView):
    permission_classes = [IsAuthenticated]

    def post(self, request, approval_id):
        ar = get_object_or_404(
            ApprovalRequest, pk=approval_id, user=request.user, status=ApprovalRequest.Status.PENDING
        )
        ar.status = ApprovalRequest.Status.REJECTED
        ar.decided_at = timezone.now()
        ar.save(update_fields=["status", "decided_at"])
        return ok({"response": {"type": "message", "text": "已取消该操作。"}})


class ConfirmPlanView(APIView):
    """
    用户在前端确认长期规划预览后，调用此接口批量创建所有任务。
    请求体：{"tasks": [...]}，每条任务格式与 plan_preview.tasks 一致。
    """
    permission_classes = [IsAuthenticated]

    def post(self, request):
        from .tools import create_tasks_batch

        tasks = request.data.get("tasks")
        if not isinstance(tasks, list) or not tasks:
            return err("VALIDATION_ERROR", "tasks 列表不能为空")
        if len(tasks) > 50:
            return err("TOO_MANY", "单次最多批量创建 50 个任务")

        client_context = request.data.get("client_context")
        if not isinstance(client_context, dict):
            client_context = None
        result = create_tasks_batch(
            user_id=str(request.user.id),
            tasks=tasks,
            client_context=client_context,
        )

        source_message_id = request.data.get("source_message_id")
        if source_message_id:
            msg = AgentMessage.objects.filter(
                pk=source_message_id,
                session__user=request.user,
                role=AgentMessage.Role.ASSISTANT,
            ).first()
            if msg and isinstance(msg.content_json, dict):
                if msg.content_json.get("type") == "plan_preview":
                    merged = dict(msg.content_json)
                    merged["plan_confirmed"] = True
                    msg.content_json = merged
                    msg.save(update_fields=["content_json"])

        created_count = result["total_created"]
        error_count = len(result["errors"])
        if created_count == 0:
            return err("CREATE_FAILED", "所有任务创建失败", result["errors"])

        text = f"已成功创建 {created_count} 个任务！"
        if error_count:
            text += f"（{error_count} 个任务创建失败）"

        return ok({
            "response": {
                "type": "message",
                "text": text,
                "created": result["created"],
                "errors": result["errors"],
            }
        })


class UserLlmConfigView(APIView):
    """获取/更新当前用户的 LLM 配置。"""

    permission_classes = [IsAuthenticated]

    def get(self, request):
        cfg = UserLlmConfig.objects.filter(user=request.user).first()
        if not cfg:
            return ok({"base_url": "", "has_api_key": False, "model_name": ""})
        return ok({
            "base_url": cfg.base_url,
            "has_api_key": bool(cfg.api_key),
            "model_name": cfg.model_name,
        })

    def patch(self, request):
        s = UserLlmConfigInSerializer(data=request.data)
        if not s.is_valid():
            return err("VALIDATION_ERROR", "输入数据无效", s.errors)

        cfg, _ = UserLlmConfig.objects.get_or_create(user=request.user)
        data = s.validated_data
        update_fields = []

        if "base_url" in data:
            raw = (data.get("base_url") or "").strip()
            cfg.base_url = raw.rstrip("/") if raw else ""
            update_fields.append("base_url")
        if "api_key" in data:
            cfg.api_key = (data.get("api_key") or "").strip()
            update_fields.append("api_key")
        if "model_name" in data:
            cfg.model_name = (data.get("model_name") or "").strip()
            update_fields.append("model_name")

        if update_fields:
            cfg.save(update_fields=update_fields + ["updated_at"])

        return ok({
            "base_url": cfg.base_url,
            "has_api_key": bool(cfg.api_key),
            "model_name": cfg.model_name,
        })


class UserLlmConfigTestView(APIView):
    """测试当前 LLM 配置是否可用。"""

    permission_classes = [IsAuthenticated]

    def post(self, request):
        s = UserLlmConfigInSerializer(data=request.data)
        if not s.is_valid():
            return err("VALIDATION_ERROR", "输入数据无效", s.errors)

        cfg = UserLlmConfig.objects.filter(user=request.user).first()
        data = s.validated_data

        base_url = data.get("base_url") if "base_url" in data else (cfg.base_url if cfg else "")
        api_key = data.get("api_key") if "api_key" in data else (cfg.api_key if cfg else "")
        model_name = data.get("model_name") if "model_name" in data else (cfg.model_name if cfg else "")

        base_url = (base_url or "").strip().rstrip("/")
        api_key = (api_key or "").strip()
        model_name = (model_name or "").strip() or getattr(settings, "AGENT_LLM_MODEL", "gpt-4o-mini")

        result = test_llm_connection(
            api_key=api_key,
            base_url=base_url or None,
            model=model_name,
        )
        if result.ok:
            return ok({
                "ok": True,
                "message": f"连接成功（模型：{model_name}）",
            })

        if result.error == "missing_api_key":
            return err("MISSING_API_KEY", "API Key 不能为空")
        if result.error == "invalid_api_key":
            return err("INVALID_API_KEY", "API Key 无效或已过期")
        if result.error == "timeout":
            return err("TIMEOUT", "连接超时，请检查网络后重试")
        if result.error == "connection_error":
            return err("CONNECTION_FAILED", "无法连接服务器，请检查 Base URL")
        return err("LLM_TEST_FAILED", "测试失败，请检查模型名称或接口配置")

