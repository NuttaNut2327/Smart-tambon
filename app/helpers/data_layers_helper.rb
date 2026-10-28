module DataLayersHelper
  def dataset_record_photo_json(dataset, photo)
    { id: photo.id.to_s, filename: photo.image["filename"],
      url: imported_dataset_record_photo_path(dataset, photo.record_id, photo),
      thumb: imported_dataset_record_photo_path(dataset, photo.record_id, photo, variant: "thumb"),
      delete_url: imported_dataset_record_photo_path(dataset, photo.record_id, photo) }
  end

  # Column header that toggles sorting while keeping the current search and filters. Sorting resets to page 1.
  def record_sort_link(label, key, query)
    active = query.sort == key
    direction = active && query.direction == "asc" ? "desc" : "asc"
    arrow = active ? (query.direction == "asc" ? "▲" : "▼") : "↕"
    link_to data_layers_path(data_type: params[:data_type], **query.to_params, sort: key, dir: direction),
            class: "record-sort#{' active' if active}", title: "เรียงตาม#{label}",
            aria: { sort: (active ? (query.direction == "asc" ? "ascending" : "descending") : nil) } do
      # The arrow is drawn by CSS so the header text stays just the column name.
      safe_join([label, tag.span(class: "record-sort-arrow", data: { arrow: }, aria: { hidden: true })])
    end
  end
end
