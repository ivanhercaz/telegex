defmodule Telegex.Request do
  @moduledoc false

  @include_attachment_methods %{
    "sendPhoto" => [:photo],
    "sendAudio" => [:audio, :thumb],
    "sendDocument" => [:document, :thumb],
    "sendVideo" => [:video, :thumb],
    "sendAnimation" => [:animation, :thumb],
    "sendVoice" => [:voice],
    "sendVideoNote" => [:video_note, :thumb],
    "setChatPhoto" => [:photo],
    "sendSticker" => [:sticker],
    "uploadStickerFile" => [:png_sticker],
    "createNewStickerSet" => [:png_sticker, :tgs_sticker],
    "addStickerToSet" => [:png_sticker, :tgs_sticker],
    "setStickerSetThumb" => [:thumb]
  }

  alias Telegex.Model.{Response, Error, RequestError}
  alias Telegex.Config

  @type result :: any()

  def call(method, params \\ []) when is_binary(method) and is_list(params) do
    endpoint = "https://api.telegram.org/bot#{Config.token()}/#{method}"

    if attach_fields = @include_attachment_methods[method] do
      post(endpoint, params, attach_fields, :multipart) |> handle_response()
    else
      post(endpoint, params) |> handle_response()
    end
  end

  @spec handle_response({:ok, HTTPoison.Response.t()}) :: {:ok, result()} | {:error, Error.t()}
  defp handle_response({:ok, %HTTPoison.Response{body: body} = _response}) do
    %Response{ok: ok, result: result, error_code: error_code, description: description} =
      structed_response(body)

    if ok,
      do: {:ok, result},
      else: {:error, %Error{error_code: error_code, description: description}}
  end

  @spec handle_response({:error, HTTPoison.Error.t()}) :: {:error, RequestError.t()}
  defp handle_response({:error, %HTTPoison.Error{reason: reason} = _response}) do
    {:error, %RequestError{reason: reason}}
  end

  @json_header {"Content-Type", "application/json"}

  @spec post(String.t(), keyword()) ::
          {:ok, HTTPoison.Response.t()} | {:error, HTTPoison.Error.t()}
  defp post(endpoint, params)
       when is_binary(endpoint) and is_list(params) do
    json_body = params |> Enum.into(%{}) |> Jason.encode!()

    HTTPoison.post(endpoint, json_body, [@json_header])
  end

  @spec post(String.t(), keyword(), [atom()], :multipart) ::
          {:ok, HTTPoison.Response.t()} | {:error, HTTPoison.Error.t()}
  defp post(endpoint, params, attach_fields, :multipart)
       when is_binary(endpoint) and is_list(params) and is_list(attach_fields) do
    no_empty_attachs =
      attach_fields
      |> Enum.map(fn field -> {field, params[field]} end)
      |> Enum.filter(fn {_, attach} -> attach != nil end)

    local_attachs = no_empty_attachs |> Enum.filter(fn {_, attach} -> File.exists?(attach) end)

    if length(local_attachs) == 0 do
      # 如果没有本地文件，则使用传统的方式请求
      post(endpoint, params)
    else
      # 1. 构建表单中的数据字段列表
      data_fields =
        params
        |> Enum.filter(fn {field, _} -> local_attachs[field] == nil end)
        |> Enum.map(fn {field, value} ->
          value =
            if is_list(value) || is_map(value), do: Jason.encode!(value), else: to_string(value)

          {to_string(field), value}
        end)

      # 2. 构建表单中的附件字段列表
      file_fields =
        local_attachs
        |> Enum.map(fn {field, file_path} ->
          {:file, file_path,
           {"form-data", [{:name, to_string(field)}, {:filename, Path.basename(file_path)}]}, []}
        end)

      multipart_form = {:multipart, data_fields ++ file_fields}

      HTTPoison.post(endpoint, multipart_form)
    end
  end

  @spec structed_response(String.t()) :: Response.t()
  defp structed_response(json) do
    data = json |> Jason.decode!(keys: :atoms)

    struct(Response, data)
  end
end
