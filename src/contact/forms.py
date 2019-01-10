import material

from django import forms
from django import template
from django.conf import settings
from django.core import validators
from django.utils.translation import gettext as _

from caisse.forms import ActiveCaisseChoiceField


MOTIF_CHOICES = (
    (None, '---------'),
    ('request_error', "J'ai fait une erreur de saisie dans mon dossier"),
    ('request_question', "J'ai une question sur mon dossier"),
    ('website_question', "J'ai une idée d'amélioration pour votre site"),
    ('other', 'Autre sujet'),
)


class ContactForm(forms.Form):
    motif = forms.ChoiceField(
        label='Motif',
        choices=MOTIF_CHOICES,
    )
    caisse = ActiveCaisseChoiceField(
        label='Votre caisse de rattachement',
    )
    nom = forms.CharField()
    email = forms.EmailField()
    mrsrequest_display_id = forms.CharField(
        label='Numéro de demande (optionnel)',
        required=False,
        max_length=12,
        validators=[
            validators.RegexValidator(
                regex=r'^\d{12}$',
                message=_('MRSREQUEST_UNEXPECTED_DISPLAY_ID'),
            )
        ]
    )
    message = forms.CharField(widget=forms.Textarea)

    layout = material.Layout(
        material.Fieldset(
            ' ',
            material.Row(
                'motif',
                'caisse',
            ),
            'mrsrequest_display_id',
            material.Row(
                'nom',
                'email',
            ),
            'message',
        )
    )

    def get_email_kwargs(self):
        data = self.cleaned_data
        to = [settings.TEAM_EMAIL]

        if data['motif'].startswith('request'):
            subject = 'RÉCLAMATION MRS'

            ''' Not to enable before product team is ready
            email = getattr(data['caisse'], 'liquidation_email', None)

            if email:  # in case caisse == 'other', let TEAM_EMAIL
                to = [email]
            '''
        else:
            subject = 'Nouveau message envoyé depuis le site'

        body = template.loader.get_template(
            'contact/contact_mail_body.txt'
        ).render(dict(
            self=self,
            motif=dict(self.fields['motif'].choices)[data['motif']],
        )).strip()

        return dict(
            subject=subject,
            body=body,
            to=to,
            reply_to=[data['email']],
        )
