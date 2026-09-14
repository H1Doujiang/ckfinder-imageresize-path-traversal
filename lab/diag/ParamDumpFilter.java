package lab;

import java.io.IOException;
import java.util.Enumeration;

import javax.servlet.Filter;
import javax.servlet.FilterChain;
import javax.servlet.FilterConfig;
import javax.servlet.ServletException;
import javax.servlet.ServletRequest;
import javax.servlet.ServletResponse;
import javax.servlet.http.HttpServletRequest;

/**
 * 诊断用过滤器：把连接器实际看到的参数原样打印到容器日志。
 * 仅用于本地实验室定位"POST 形态 Init 返回 109"的原因，不属于复现链路。
 */
public class ParamDumpFilter implements Filter {

    @Override
    public void init(FilterConfig cfg) {
    }

    @Override
    public void doFilter(ServletRequest req, ServletResponse res, FilterChain chain)
            throws IOException, ServletException {
        HttpServletRequest r = (HttpServletRequest) req;
        StringBuilder sb = new StringBuilder();
        sb.append("[ParamDump] ").append(r.getMethod()).append(' ')
          .append(r.getRequestURI());
        if (r.getQueryString() != null) {
            sb.append('?').append(r.getQueryString());
        }
        sb.append("  contentType=").append(r.getContentType())
          .append("  charEncoding=").append(r.getCharacterEncoding());
        Enumeration<String> names = r.getParameterNames();
        while (names.hasMoreElements()) {
            String n = names.nextElement();
            String[] vs = r.getParameterValues(n);
            sb.append("  | ").append(n).append('=');
            for (int i = 0; i < vs.length; i++) {
                if (i > 0) {
                    sb.append(',');
                }
                sb.append('[').append(vs[i]).append(']');
            }
        }
        System.out.println(sb.toString());
        chain.doFilter(req, res);
    }

    @Override
    public void destroy() {
    }
}
