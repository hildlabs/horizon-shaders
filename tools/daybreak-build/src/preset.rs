//! A quality preset and what it changes in the source pack: the manifest's id, name, shadow
//! map, budget and option defaults, and the WGSL lines tagged for features it leaves out.

use serde::Deserialize;
use toml_edit::{DocumentMut, Item, value};

/// `presets.toml`.
#[derive(Debug, Deserialize)]
pub struct Presets {
    pub preset: Vec<Preset>,
}

#[derive(Debug, Deserialize)]
pub struct Preset {
    /// Appended to the source pack's id: `daybreak` becomes `daybreak_<id>`.
    pub id: String,
    /// Appended to the pack's name: "Daybreak Low".
    pub name: String,
    /// Put before the pack's own description.
    pub description: String,
    /// `[budget] gpu_ms`.
    pub gpu_ms: f32,
    /// The shadow map's `[shadow]` values; none for no shadow map.
    pub shadow: Option<Shadow>,
    /// Keep the terrain mask the composite shades mobs by (WGSL lines tagged
    /// `preset:mob-shadows`).
    #[serde(default = "yes")]
    pub mob_shadows: bool,
    /// Option defaults, by option id.
    #[serde(default)]
    pub defaults: toml::Table,
}

#[derive(Debug, Deserialize)]
pub struct Shadow {
    pub resolution: u32,
    pub distance: f32,
}

fn yes() -> bool {
    true
}

/// The tag of WGSL lines only the mob shadows need.
pub const MOB_SHADOWS_TAG: &str = "preset:mob-shadows";

impl Preset {
    /// The source manifest `manifest` as this preset's pack.
    pub fn manifest(&self, manifest: &str) -> Result<String, String> {
        let mut doc: DocumentMut = manifest
            .parse()
            .map_err(|e| format!("horizon-shaders.toml: {e}"))?;
        let text = |doc: &DocumentMut, key: &str| -> Result<String, String> {
            doc.get(key)
                .and_then(Item::as_str)
                .map(str::to_owned)
                .ok_or_else(|| format!("horizon-shaders.toml has no `{key}`"))
        };
        let id = text(&doc, "id")?;
        let name = text(&doc, "name")?;
        let description = text(&doc, "description").unwrap_or_default();
        doc["id"] = value(format!("{id}_{}", self.id));
        doc["name"] = value(format!("{name} {}", self.name));
        doc["description"] = value(format!("{} {description}", self.description));

        match &self.shadow {
            None => {
                doc.remove("shadow");
            }
            Some(shadow) => {
                let table = doc
                    .get_mut("shadow")
                    .and_then(Item::as_table_mut)
                    .ok_or("the source pack has no [shadow] to set")?;
                table["resolution"] = value(i64::from(shadow.resolution));
                table["distance"] = value(f64::from(shadow.distance));
            }
        }
        doc["budget"]["gpu_ms"] = value(f64::from(self.gpu_ms));

        let options = doc
            .get_mut("options")
            .and_then(Item::as_array_of_tables_mut)
            .ok_or("horizon-shaders.toml has no [[options]]")?;
        for (key, default) in &self.defaults {
            let option = options
                .iter_mut()
                .find(|o| o.get("id").and_then(Item::as_str) == Some(key))
                .ok_or_else(|| format!("preset {}: no option `{key}`", self.id))?;
            let kind = option.get("type").and_then(Item::as_str).unwrap_or_default();
            option["default"] = default_value(kind, default)
                .ok_or_else(|| format!("preset {}: `{key}` is a {kind} option", self.id))?;
        }
        Ok(doc.to_string())
    }

    /// The WGSL file `source` for this preset: the lines of features it leaves out removed.
    pub fn wgsl(&self, source: &str) -> String {
        if self.mob_shadows {
            return source.to_owned();
        }
        source
            .split_inclusive('\n')
            .filter(|line| !line.contains(MOB_SHADOWS_TAG))
            .collect()
    }
}

/// `default` as the value of an option of type `kind`: a whole number for a float option is
/// still a float, and a choice takes the name of one of its values.
fn default_value(kind: &str, default: &toml::Value) -> Option<Item> {
    use toml::Value as V;
    Some(match (kind, default) {
        ("bool", V::Boolean(b)) => value(*b),
        ("float", V::Float(f)) => value(*f),
        ("float", V::Integer(i)) => value(*i as f64),
        ("int", V::Integer(i)) => value(*i),
        ("choice", V::String(s)) => value(s.as_str()),
        _ => return None,
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    const MANIFEST: &str = r#"schema = 1
id = "daybreak"
name = "Daybreak"
version = "0.1.0"
description = "Shaders."

[shadow]
resolution = 2048
# kept
distance = 96.0

[budget]
gpu_ms = 2.5

[[options]]
id = "shadows"
type = "bool"
default = true

[[options]]
id = "god_rays"
type = "float"
default = 0.5

[[options]]
id = "shadow_softness"
type = "choice"
values = ["Sharp", "Soft"]
default = "Soft"
"#;

    fn preset(text: &str) -> Preset {
        toml::from_str(text).unwrap()
    }

    #[test]
    fn names_the_pack_after_its_preset() {
        let p = preset("id = \"low\"\nname = \"Low\"\ndescription = \"Fast.\"\ngpu_ms = 0.5\n");
        let out: DocumentMut = p.manifest(MANIFEST).unwrap().parse().unwrap();
        assert_eq!(out["id"].as_str(), Some("daybreak_low"));
        assert_eq!(out["name"].as_str(), Some("Daybreak Low"));
        assert_eq!(out["description"].as_str(), Some("Fast. Shaders."));
        assert_eq!(out["budget"]["gpu_ms"].as_float(), Some(0.5));
    }

    #[test]
    fn no_shadow_removes_the_shadow_map() {
        let p = preset("id = \"low\"\nname = \"Low\"\ndescription = \"\"\ngpu_ms = 0.5\n");
        let out: DocumentMut = p.manifest(MANIFEST).unwrap().parse().unwrap();
        assert!(out.get("shadow").is_none());
    }

    #[test]
    fn sets_the_shadow_map_and_keeps_comments() {
        let p = preset(
            "id = \"ultra\"\nname = \"Ultra\"\ndescription = \"\"\ngpu_ms = 3.5\n\
             shadow = { resolution = 4096, distance = 160.0 }\n",
        );
        let text = p.manifest(MANIFEST).unwrap();
        assert!(text.contains("# kept"));
        let out: DocumentMut = text.parse().unwrap();
        assert_eq!(out["shadow"]["resolution"].as_integer(), Some(4096));
        assert_eq!(out["shadow"]["distance"].as_float(), Some(160.0));
    }

    #[test]
    fn sets_option_defaults_by_type() {
        let p = preset(
            "id = \"low\"\nname = \"Low\"\ndescription = \"\"\ngpu_ms = 0.5\n\
             [defaults]\nshadows = false\ngod_rays = 0\nshadow_softness = \"Sharp\"\n",
        );
        let out: DocumentMut = p.manifest(MANIFEST).unwrap().parse().unwrap();
        let options = out["options"].as_array_of_tables().unwrap();
        let default = |id: &str| {
            options
                .iter()
                .find(|o| o["id"].as_str() == Some(id))
                .unwrap()["default"]
                .clone()
        };
        assert_eq!(default("shadows").as_bool(), Some(false));
        assert_eq!(default("god_rays").as_float(), Some(0.0));
        assert_eq!(default("shadow_softness").as_str(), Some("Sharp"));
    }

    #[test]
    fn refuses_unknown_options_and_wrong_types() {
        let unknown = preset(
            "id = \"x\"\nname = \"X\"\ndescription = \"\"\ngpu_ms = 1\n[defaults]\nnope = true\n",
        );
        assert!(unknown.manifest(MANIFEST).unwrap_err().contains("no option `nope`"));
        let wrong = preset(
            "id = \"x\"\nname = \"X\"\ndescription = \"\"\ngpu_ms = 1\n[defaults]\nshadows = 1\n",
        );
        assert!(wrong.manifest(MANIFEST).unwrap_err().contains("bool option"));
    }

    #[test]
    fn drops_mob_shadow_lines_only_without_them() {
        let source = "a();\nset_surface(n); // preset:mob-shadows\nb();\n";
        let without = preset(
            "id = \"low\"\nname = \"Low\"\ndescription = \"\"\ngpu_ms = 0.5\nmob_shadows = false\n",
        );
        assert_eq!(without.wgsl(source), "a();\nb();\n");
        let with = preset("id = \"high\"\nname = \"High\"\ndescription = \"\"\ngpu_ms = 2\n");
        assert_eq!(with.wgsl(source), source);
    }
}
