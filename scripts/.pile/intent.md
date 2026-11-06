The steps the action runs on a runner, each one a script that needs only bash and the tools every GitHub runner has.

Getting `pile`, running it, keeping the comments on the pull request, the one command an agent posts its review with, and filling the prompt belong here, and so does what each step does when something it needs is missing. Among them is the filling of the placeholders a template may use, and the cleaning of what the pull request's author wrote before it reaches the prompt. Words meant for an agent do not belong here.

Read this pile to find out what a step does on a runner, and what it does when something is missing. Change it when `pile`, GitHub or a runner changes what a step can rely on.
