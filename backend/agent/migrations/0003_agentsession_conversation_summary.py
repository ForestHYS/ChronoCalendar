from django.db import migrations, models


class Migration(migrations.Migration):

    dependencies = [
        ("agent", "0002_approvalrequest"),
    ]

    operations = [
        migrations.AddField(
            model_name="agentsession",
            name="conversation_summary",
            field=models.TextField(blank=True, default=""),
        ),
        migrations.AddField(
            model_name="agentsession",
            name="summary_through_id",
            field=models.UUIDField(blank=True, null=True),
        ),
    ]
