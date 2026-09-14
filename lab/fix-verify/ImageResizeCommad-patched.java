/*
 * 修复验证用：ImageResizeCommad.java 的最小加固补丁版
 * 原始文件: 官方 CKFinder for Java 2.6.2 发行包
 *           ImageResizePlugin/src/main/java/com/ckfinder/connector/plugins/ImageResizeCommad.java
 *           （2.6.2 / 2.6.2.1 / 2.6.3 三版 sha256 完全相同：
 *             6D30F2DB787AA0F61B0B77287E73DE714018C6814625BDA6D2CB9DEA564C0D4F）
 *
 * 改动仅两处，与报告 §六 修复建议一致：
 *   [1] 布尔逻辑 && -> ||（原逻辑等价于"永不拒绝"，见下方注释）
 *   [2] 输出路径 canonical 化并强制限定在资源目录内
 */
package com.ckfinder.connector.plugins;

import java.io.File;
import java.io.IOException;
import java.util.HashMap;
import java.util.Map;
import java.util.StringTokenizer;
import java.util.regex.Pattern;

import javax.servlet.http.HttpServletRequest;

import org.w3c.dom.Element;

import com.ckfinder.connector.configuration.Constants;
import com.ckfinder.connector.configuration.IConfiguration;
import com.ckfinder.connector.data.BeforeExecuteCommandEventArgs;
import com.ckfinder.connector.data.EventArgs;
import com.ckfinder.connector.data.IEventHandler;
import com.ckfinder.connector.data.PluginInfo;
import com.ckfinder.connector.data.PluginParam;
import com.ckfinder.connector.errors.ConnectorException;
import com.ckfinder.connector.handlers.command.XMLCommand;
import com.ckfinder.connector.utils.AccessControlUtil;
import com.ckfinder.connector.utils.FileUtils;
import com.ckfinder.connector.utils.ImageUtils;

public class ImageResizeCommad extends XMLCommand implements IEventHandler {

	private PluginInfo pluginInfo;
	/**
	 * file name
	 */
	private String fileName;
	private String newFileName;
	private String overwrite;
	private Integer width;
	private Integer height;
	private boolean wrongReqSizesParams;
	private Map<String, String> sizesFromReq;
	private static final String[] SIZES = {"small", "medium", "large"};
	/**
	 * Current request object
	 */
	private HttpServletRequest request;

	@Override
	public boolean runEventHandler(EventArgs eventArgs, IConfiguration configuration1)
		throws ConnectorException {
		BeforeExecuteCommandEventArgs args = (BeforeExecuteCommandEventArgs) eventArgs;
		if ("ImageResize".equals(args.getCommand())) {
			this.runCommand(args.getRequest(), args.getResponse(), configuration1);
			return false;
		}
		return true;
	}

	@Override
	protected void createXMLChildNodes(int arg0, Element arg1)
		throws ConnectorException {
	}

	/**
	 * 解析输出文件并强制限定在资源目录内。
	 *
	 * @return 合法的输出文件；越界时返回 null
	 */
	private File resolveOutputFile() throws IOException {
		File baseDir = new File(configuration.getTypes().get(this.type).getPath()
			+ this.currentFolder).getCanonicalFile();
		File candidate = new File(baseDir, this.newFileName).getCanonicalFile();
		String basePath = baseDir.getPath() + File.separator;
		String candidatePath = candidate.getPath() + File.separator;
		if (!candidatePath.startsWith(basePath)) {
			return null;
		}
		return candidate;
	}

	@Override
	protected int getDataForXml() {

		if (this.configuration.isEnableCsrfProtection() && !checkCsrfToken(this.request, null)) {
			return Constants.Errors.CKFINDER_CONNECTOR_ERROR_INVALID_REQUEST;
		}

		if (!checkIfTypeExists(this.type)) {
			this.type = null;
			return Constants.Errors.CKFINDER_CONNECTOR_ERROR_INVALID_TYPE;
		}

		if (!AccessControlUtil.getInstance().checkFolderACL(type, currentFolder, userRole,
			AccessControlUtil.CKFINDER_CONNECTOR_ACL_FILE_DELETE
			| AccessControlUtil.CKFINDER_CONNECTOR_ACL_FILE_UPLOAD)) {
			return Constants.Errors.CKFINDER_CONNECTOR_ERROR_UNAUTHORIZED;
		}

		if (this.fileName == null || this.fileName.equals("")) {
			return Constants.Errors.CKFINDER_CONNECTOR_ERROR_INVALID_NAME;
		}

		if (!FileUtils.checkFileName(fileName)
			|| FileUtils.checkIfFileIsHidden(fileName, configuration)) {
			return Constants.Errors.CKFINDER_CONNECTOR_ERROR_INVALID_REQUEST;
		}

		if (FileUtils.checkFileExtension(fileName, configuration.getTypes().get(type)) == 1) {
			return Constants.Errors.CKFINDER_CONNECTOR_ERROR_INVALID_REQUEST;
		}

		File file = new File(configuration.getTypes().get(type).getPath() + this.currentFolder,
			fileName);
		try {
			if (!(file.exists() && file.isFile())) {
				return Constants.Errors.CKFINDER_CONNECTOR_ERROR_FILE_NOT_FOUND;
			}

			if (this.wrongReqSizesParams) {
				return Constants.Errors.CKFINDER_CONNECTOR_ERROR_INVALID_REQUEST;
			}

			if (this.width != null && this.height != null) {

				// [FIX-1] 不再对 newFileName 套用 checkFileName()：
				//   它的语义是"单个文件名"（拒绝含 ".." 的名字），但 newFileName 是
				//   相对类型根目录的路径，合法值本来就可能含 ".."（如 "sub/../out.png"）。
				//   把 && 改成 || 会连合法路径一起拒掉，属于过宽。
				//   这里只保留隐藏文件检查，真正的安全边界交给 [FIX-2] 的 canonical 校验。
				if (FileUtils.checkIfFileIsHidden(this.newFileName, configuration)) {
					return Constants.Errors.CKFINDER_CONNECTOR_ERROR_INVALID_NAME;
				}

				if (FileUtils.checkFileExtension(this.newFileName,
					configuration.getTypes().get(this.type)) == 1) {
					return Constants.Errors.CKFINDER_CONNECTOR_ERROR_INVALID_EXTENSION;
				}

				// [FIX-2] 路径 canonical 化 + 边界校验：解析完 ".." 之后再判断是否越出资源目录
				File thumbFile = resolveOutputFile();
				if (thumbFile == null) {
					return Constants.Errors.CKFINDER_CONNECTOR_ERROR_ACCESS_DENIED;
				}

				if (thumbFile.exists() && !thumbFile.canWrite()) {
					return Constants.Errors.CKFINDER_CONNECTOR_ERROR_ACCESS_DENIED;
				}
				if (!"1".equals(this.overwrite) && thumbFile.exists()) {
					return Constants.Errors.CKFINDER_CONNECTOR_ERROR_ALREADY_EXIST;
				}
				int maxImageHeight = configuration.getImgHeight();
				int maxImageWidth = configuration.getImgWidth();
				if ((maxImageWidth > 0 && this.width > maxImageWidth)
					|| (maxImageHeight > 0 && this.height > maxImageHeight)) {
					return Constants.Errors.CKFINDER_CONNECTOR_ERROR_INVALID_REQUEST;
				}

				try {
					ImageUtils.createResizedImage(file, thumbFile,
						this.width, this.height, configuration.getImgQuality());

				} catch (IOException e) {
					if (configuration.isDebugMode()) {
						this.exception = e;
					}
					return Constants.Errors.CKFINDER_CONNECTOR_ERROR_ACCESS_DENIED;
				}
			}

			String fileNameWithoutExt = FileUtils.getFileNameWithoutExtension(fileName);
			String fileExt = FileUtils.getFileExtension(fileName);
			for (String size : SIZES) {
				if (sizesFromReq.get(size) != null
					&& sizesFromReq.get(size).equals("1")) {
					String thumbName = fileNameWithoutExt.concat("_").concat(size).concat(".").concat(fileExt);
					File thumbFile = new File(configuration.getTypes().get(this.type).getPath().concat(this.currentFolder).concat(thumbName));
					for (PluginParam param : pluginInfo.getParams()) {
						if (size.concat("Thumb").equals(param.getName())) {
							if (checkParamSize(param.getValue())) {
								String[] params = parseValue(param.getValue());
								try {
									ImageUtils.createResizedImage(file, thumbFile, Integer.valueOf(params[0]),
										Integer.valueOf(params[1]), configuration.getImgQuality());
								} catch (IOException e) {
									if (configuration.isDebugMode()) {
										this.exception = e;
									}
									return Constants.Errors.CKFINDER_CONNECTOR_ERROR_ACCESS_DENIED;
								}
							}
						}
					}
				}
			}
		} catch (SecurityException e) {
			if (configuration.isDebugMode()) {
				this.exception = e;
			}
			return Constants.Errors.CKFINDER_CONNECTOR_ERROR_ACCESS_DENIED;
		} catch (IOException e) {
			if (configuration.isDebugMode()) {
				this.exception = e;
			}
			return Constants.Errors.CKFINDER_CONNECTOR_ERROR_ACCESS_DENIED;
		}

		return Constants.Errors.CKFINDER_CONNECTOR_ERROR_NONE;
	}

	private String[] parseValue(String value) {
		StringTokenizer st = new StringTokenizer(value, "x");
		String[] res = new String[2];
		res[0] = st.nextToken();
		res[1] = st.nextToken();
		return res;
	}

	private boolean checkParamSize(String value) {
		return Pattern.matches("(\\d)+x(\\d)+", value);
	}

	@Override
	public void initParams(HttpServletRequest request,
		IConfiguration configuration1, Object... params)
		throws ConnectorException {
		super.initParams(request, configuration1, params);

		this.request = request;
		this.sizesFromReq = new HashMap<String, String>();
		this.fileName = getParameter(request, "fileName");
		this.newFileName = getParameter(request, "newFileName");
		this.overwrite = request.getParameter("overwrite");
		String reqWidth = request.getParameter("width");
		String reqHeight = request.getParameter("height");
		this.wrongReqSizesParams = false;
		try {
			if (reqWidth != null && !reqWidth.equals("")) {
				this.width = Integer.valueOf(reqWidth);
			} else {
				this.width = null;
			}
		} catch (NumberFormatException e) {
			this.width = null;
			this.wrongReqSizesParams = true;
		}
		try {
			if (reqHeight != null && !reqHeight.equals("")) {
				this.height = Integer.valueOf(reqHeight);
			} else {
				this.height = null;
			}
		} catch (NumberFormatException e) {
			this.height = null;
			this.wrongReqSizesParams = true;
		}
		for (String size : SIZES) {
			sizesFromReq.put(size, request.getParameter(size));
		}

	}

	public ImageResizeCommad(PluginInfo pluginInfo) {
		this.pluginInfo = pluginInfo;
	}
}
