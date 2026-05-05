from django.shortcuts import get_object_or_404
from rest_framework.permissions import IsAuthenticated
from rest_framework.views import APIView

from tasks.views import err, ok

from .graph import build_graph
from .models import AgentMessage, AgentSession
from .serializers import AgentMessageInSerializer, AgentMessageOutSerializer, AgentSessionSerializer


_graph = None


def _get_graph():
    global _graph
    if _graph is None:
        _graph = build_graph()
    return _graph


class AgentSessionCreateView(APIView):
    permission_classes = [IsAuthenticated]

    def post(self, request):
        s = AgentSession.objects.create(user=request.user)
        return ok(AgentSessionSerializer(s).data)


class AgentMessageCreateView(APIView):
    permission_classes = [IsAuthenticated]

    def post(self, request, session_id):
        session = get_object_or_404(AgentSession, pk=session_id, user=request.user)
        ins = AgentMessageInSerializer(data=request.data)
        if not ins.is_valid():
            return err("VALIDATION_ERROR", "输入数据无效", ins.errors)

        text = ins.validated_data["text"]
        client_context = ins.validated_data.get("client_context") or {}

        AgentMessage.objects.create(session=session, role=AgentMessage.Role.USER, content_text=text)

        try:
            graph = _get_graph()
            state = {
                "user_id": str(request.user.id),
                "input_text": text,
                "client_context": client_context,
            }
            out = graph.invoke(state)
            resp = out.get("response") if isinstance(out, dict) else None
            if not isinstance(resp, dict):
                resp = {"type": "message", "text": "系统繁忙，请稍后重试。"}
        except Exception:
            # Agent 不应因 LLM/解析失败导致 500；统一降级为可读提示
            resp = {
                "type": "message",
                "text": "AI 解析暂时不可用（可能是 LLM 配置无效）。你也可以直接用任务编辑页创建，或稍后再试。",
            }

        AgentMessage.objects.create(
            session=session,
            role=AgentMessage.Role.ASSISTANT,
            content_text=resp.get("text") or resp.get("message") or "",
            content_json=resp,
        )
        session.save(update_fields=["updated_at"])

        return ok({"response": resp})

