---
layout: default.liquid
pagination:
  include: All
  per_page: 5
  permalink_suffix: "./{{ num }}/"
  order: Desc
  sort_by: ["published_date"]
  date_index: ["Year", "Month"]
---
## Under the hood

I am Alejandro, an enthusiastic Software Engineer; I work in IT and I like
the low level world; Between my hobbies I like music production (Ableton live),
and food. I am not sporty but sometimes I practice hicking and running for
keeping myself healthier.

{% for post in paginator.pages limit:5 %}
#### [{{ post.title }}]({{ post.permalink }})

{{ post.excerpt }}

{% endfor %}

<center>

{% if paginator.previous_index %}[First](/{{ paginator.first_index_permalink }}){% endif %} | {% if paginator.previous_index %}[Previous](/{{ paginator.previous_index_permalink }}){% endif %} | {% if paginator.next_index %}[Next](/{{ paginator.next_index_permalink }}){% endif %} | {% if paginator.next_index %}[Last](/{{ paginator.last_index_permalink }}){% endif %}

({{ paginator.index }} / {{ paginator.total_indexes }})

</center>
