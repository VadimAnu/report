﻿/** Reporting.mqh
 ... (комментарии остаются) ...
*/
// Проверка, что мы работаем именно в MQL5
#ifdef __MQL4__
  #error Этот код предназначен только для MQL5
#endif

// Подключаем стандартные библиотеки, если нужно
#include <Trade/Trade.mqh>       // Используем прямые слеши / Use forward slashes
#include <Arrays/ArrayObj.mqh>       // Для CArrayObj (массив объектов) / For CArrayObj
#include <Arrays/ArrayString.mqh> // Для CArrayString (массив строк) / For CArrayString
#include <Arrays/ArrayLong.mqh>    // For CArrayLong (timestamp arrays)


// Define assert for debug purposes
#define assert(expression) if(!(expression)) { Print("Assertion failed: ", #expression, ", file ", __FILE__, ", line ", __LINE__); }

// Пространство имён для отчёта
namespace REPORT
{
   // Define the missing AccountInfoPlus structure
   struct AccountInfoPlus
   {
     long    login;
     double balance;
     double equity;
     double margin;
     double margin_free;
   };
   
   
   // Inside namespace REPORT, or globally if preferred
   struct SymbolPnlPoint // This can remain a struct as it's used in a dynamic array within a class
   {
       datetime time;
       double   cumulativePnl;
   };
   
   class CSymbolPnlSeries : public CObject // Должен наследоваться от CObject для хранения в CArrayObj
   {
   public:
       string          m_symbol_name;
       SymbolPnlPoint  m_pnl_points[]; // Динамический массив точек P/L

       // Конструктор
       CSymbolPnlSeries(string name = "") : m_symbol_name(name)
       {
           ArrayFree(m_pnl_points); // Инициализация
       }

       void AddPoint(datetime time_val, double pnl_val) // Изменены имена параметров во избежание конфликтов
       {
           int size = ArraySize(m_pnl_points);
           ArrayResize(m_pnl_points, size + 1);
           m_pnl_points[size].time = time_val;
           m_pnl_points[size].cumulativePnl = pnl_val;
       }
       
       // Для сортировки
       virtual int Compare(const CObject *node, const int mode = 0) const override 
       {
           const CSymbolPnlSeries *other = (const CSymbolPnlSeries *)node;
           return StringCompare(m_symbol_name, other.m_symbol_name);
       }
   };
   
   // ИЗМЕНЕНО: struct DealInfo на class DealInfo : public CObject
   // MODIFIED: struct DealInfo to class DealInfo : public CObject
   class DealInfo : public CObject // Должен наследоваться от CObject
   {
   public:
       datetime time;
       double   net_pl;
       string   symbol;

       // Конструктор по умолчанию (необходим для CObject)
       DealInfo() : time(0), net_pl(0.0), symbol("") {} 
   };

   // Function to get cumulative P/L data for symbols and generate chart HTML   // Function to get cumulative P/L data for symbols and generate chart HTML
   string GetCumulativeSymbolPnlChart(datetime startTime, datetime endTime, const int maxSymbols = 5)
   {
       Print(__FUNCTION__, ": Расчет кумулятивного P/L по символам за период [", TimeToString(startTime, TIME_DATE), " - ", TimeToString(endTime, TIME_DATE), "]");
       string chart_html_output = StringFormat("<h3>%s</h3>\n", "Кумулятивная прибыль по инструментам");
   
       if (!HistorySelect(startTime, endTime))
       {
           Print(__FUNCTION__, ": Ошибка выбора истории.");
           return chart_html_output + "<div class=\"empty-chart-message\">Ошибка получения истории сделок для графика кумулятивной прибыли.</div>";
       }
   
       int total_deals_in_period = HistoryDealsTotal();
       if (total_deals_in_period == 0)
       {
           return chart_html_output + "<div class=\"empty-chart-message\">Нет сделок за указанный период для графика кумулятивной прибыли.</div>";
       }
   
       CArrayObj all_relevant_deals; 
   
       for (int i = 0; i < total_deals_in_period; i++)
       {
           ulong deal_ticket = HistoryDealGetTicket(i);
           if (deal_ticket == 0) continue;
   
           ENUM_DEAL_TYPE deal_type = (ENUM_DEAL_TYPE)HistoryDealGetInteger(deal_ticket, DEAL_TYPE);
           if (deal_type != DEAL_TYPE_BUY && deal_type != DEAL_TYPE_SELL) continue;
   
           DealInfo *deal_info_ptr = new DealInfo(); // Используем указатель
           deal_info_ptr.time = (datetime)HistoryDealGetInteger(deal_ticket, DEAL_TIME);
           deal_info_ptr.net_pl = HistoryDealGetDouble(deal_ticket, DEAL_PROFIT) +
                                  HistoryDealGetDouble(deal_ticket, DEAL_COMMISSION) +
                                  HistoryDealGetDouble(deal_ticket, DEAL_SWAP);
           deal_info_ptr.symbol = HistoryDealGetString(deal_ticket, DEAL_SYMBOL);
           
           all_relevant_deals.Add(deal_info_ptr); // Добавляем указатель
       }
       
       if(all_relevant_deals.Total() == 0)
       {
           all_relevant_deals.FreeMode(true); 
           all_relevant_deals.Shutdown();
           return chart_html_output + "<div class=\"empty-chart-message\">Не найдено торговых сделок (Buy/Sell) для графика.</div>";
       }
       
       CArrayObj pnl_series_list; 
   
       for(int i = 0; i < all_relevant_deals.Total(); i++)
       {
           DealInfo* deal_info_ptr = (DealInfo*)all_relevant_deals.At(i);
           if(deal_info_ptr == NULL) continue;
   
           CSymbolPnlSeries* current_symbol_series = NULL;
           for(int j = 0; j < pnl_series_list.Total(); j++)
           {
               CSymbolPnlSeries* series_ptr = (CSymbolPnlSeries*)pnl_series_list.At(j); // Исправлено
               if(series_ptr != NULL && series_ptr.m_symbol_name == deal_info_ptr.symbol) // ИЗМЕНЕНО: -> и проверка на NULL
               {
                   current_symbol_series = series_ptr;
                   break;
               }
           }
   
           if(current_symbol_series == NULL)
           {
               current_symbol_series = new CSymbolPnlSeries(deal_info_ptr.symbol); // ИЗМЕНЕНО: ->
               if(!pnl_series_list.Add(current_symbol_series))
               {
                   delete current_symbol_series;
                   continue;
               }
           }
           current_symbol_series.AddPoint(deal_info_ptr.time, deal_info_ptr.net_pl); // ИЗМЕНЕНО: ->
       }
       
       all_relevant_deals.FreeMode(true);
       all_relevant_deals.Shutdown();
   
       for(int i = 0; i < pnl_series_list.Total(); i++)
       {
           CSymbolPnlSeries* series = (CSymbolPnlSeries*)pnl_series_list.At(i);
           if(series == NULL || ArraySize(series.m_pnl_points) == 0) continue; // ИЗМЕНЕНО: ->
   
           // Sort points by time
           for(int j = 0; j < ArraySize(series.m_pnl_points) - 1; j++)
           {
               for(int k = 0; k < ArraySize(series.m_pnl_points) - j - 1; k++)
               {
                   if(series.m_pnl_points[k].time > series.m_pnl_points[k+1].time)
                   {
                       SymbolPnlPoint temp = series.m_pnl_points[k];
                       series.m_pnl_points[k] = series.m_pnl_points[k+1];
                       series.m_pnl_points[k+1] = temp;
                   }
               }
           }
           
           // Calculate cumulative P/L
           double cumulative_sum = 0;
           for(int j = 0; j < ArraySize(series.m_pnl_points); j++)
           {
               cumulative_sum += series.m_pnl_points[j].cumulativePnl;
               series.m_pnl_points[j].cumulativePnl = cumulative_sum;
           }
       }
   
       string chart_datasets_js = ""; // Renamed for clarity
       string global_labels_js_array = ""; 
       
       CArrayLong unique_timestamps_long_obj;
       for(int i = 0; i < pnl_series_list.Total(); i++)
       {
           CSymbolPnlSeries* series = (CSymbolPnlSeries*)pnl_series_list.At(i);
           if(series == NULL) continue;
           for(int j = 0; j < ArraySize(series.m_pnl_points); j++)
           {
               bool found = false;
               for(int k=0; k < unique_timestamps_long_obj.Total(); k++) {
                   if((datetime)unique_timestamps_long_obj.At(k) == series.m_pnl_points[j].time) {
                       found = true;
                       break;
                   }
               }
               if(!found) unique_timestamps_long_obj.Add(series.m_pnl_points[j].time);
           }
       }
       unique_timestamps_long_obj.Sort(); 
       
       int total_unique_timestamps = unique_timestamps_long_obj.Total();
   
       for(int i = 0; i < total_unique_timestamps; i++)
       {
           if(i > 0) global_labels_js_array += ",";
           global_labels_js_array += "'" + TimeToString((datetime)unique_timestamps_long_obj.At(i), TIME_DATE | TIME_MINUTES) + "'";
       }
   
       // Modern color palette with higher contrast and better readability on dark backgrounds
       //string colors[] = {"#4f8df5", "#ff5252", "#00c853", "#ffab40", "#aa00ff", "#18ffff", "#ffd740", "#e040fb"};
       string colors[] = {
          "#2196F3", // Bright blue
          "#FF5252", // Red
          "#00E676", // Bright green
          "#FFAB00", // Amber
          "#7C4DFF", // Deep purple
          "#18FFFF", // Cyan
          "#F50057", // Pink
          "#FFEB3B", // Yellow
          //"#00B0FF", // Light blue
          "#ff00ff",
          "#76FF03", // Light green
          "#FF3D00", // Deep orange
          "#651FFF", // Purple
          "#64FFDA", // Teal
          "#FF9100", // Orange
          "#1DE9B6", // Mint
          "#F44336", // Material red
          "#EEFF41", // Lime
          "#E91E63", // Material pink
          "#03A9F4", // Material blue
          "#CDDC39"  // Lime green
      };
       for (int i = 0; i < pnl_series_list.Total(); i++)
       {
           CSymbolPnlSeries* series = (CSymbolPnlSeries*)pnl_series_list.At(i);
           if (series == NULL || ArraySize(series.m_pnl_points) == 0) continue;
   
           if (chart_datasets_js != "") chart_datasets_js += ",\n"; 
   
           string symbol_data_js_array = "";
           int current_point_index_for_series = 0; // Для оптимизации поиска точек PNL для каждого символа
   
           for(int ts_idx = 0; ts_idx < total_unique_timestamps; ts_idx++)
           {
               datetime global_time = (datetime)unique_timestamps_long_obj.At(ts_idx);
               
               if(ts_idx > 0) symbol_data_js_array += ",";
   
               double current_ts_pnl = 0; 
               
               // Находим последнюю точку PNL для данного символа, которая <= global_time
               // Предполагается, что series.m_pnl_points уже отсортирован по времени
               bool found_deal_for_time = false;
               for(int pt_idx = current_point_index_for_series; pt_idx < ArraySize(series.m_pnl_points); pt_idx++) {
                   if(series.m_pnl_points[pt_idx].time <= global_time) {
                       current_ts_pnl = series.m_pnl_points[pt_idx].cumulativePnl;
                       current_point_index_for_series = pt_idx; // Обновляем индекс, чтобы начать следующий поиск с этой точки
                       found_deal_for_time = true;
                   } else {
                       break; // Точки отсортированы, дальше будут только более поздние.
                   }
               }
               
               // Если для текущего global_time не найдено точки символа, используем значение из предыдущей точки.
               // Это происходит, когда global_time попадает между двумя сделками символа или до первой сделки символа.
               if (!found_deal_for_time) {
                   if (ArraySize(series.m_pnl_points) > 0) {
                       if (global_time < series.m_pnl_points[0].time) {
                           current_ts_pnl = 0; // До первой сделки символа PNL = 0
                       } else {
                           // Используем PNL из последней найденной (или предыдущей) точки символа
                           if (current_point_index_for_series >= 0 && current_point_index_for_series < ArraySize(series.m_pnl_points)) {
                               current_ts_pnl = series.m_pnl_points[current_point_index_for_series].cumulativePnl;
                           } else {
                               current_ts_pnl = 0; // Fallback, should not happen if logic is perfect
                           }
                       }
                   } else {
                       current_ts_pnl = 0; // В серии нет точек вообще
                   }
               }
               
               symbol_data_js_array += DoubleToString(current_ts_pnl, 2);
           }
           
           string dataset_line_color = colors[i % ArraySize(colors)];
   
           chart_datasets_js += StringFormat(
               "         {\n"
               "            label: '%s',\n"
               "            data: [%s],\n"
               "            borderColor: '%s',\n"
               "            backgroundColor: '%s',\n" 
               "            fill: false,\n" // No fill for multiple lines normally
               "            tension: 0.1,\n"
               "            pointRadius: 2,\n" 
               "            pointHoverRadius: 5,\n"
               "            borderWidth: 1.0\n" // Thinner lines as requested
               "        }",
               series.m_symbol_name,
               symbol_data_js_array,
               dataset_line_color,
               dataset_line_color
           );
       }
       
       // Cleanup
       unique_timestamps_long_obj.Shutdown(); 
       pnl_series_list.FreeMode(true);
       pnl_series_list.Shutdown();
   
       if(chart_datasets_js == "") {
           return chart_html_output + "<div class=\"empty-chart-message\">Нет данных для построения графика кумулятивной прибыли.</div>";
       }
   
      chart_html_output += "<div class=\"chart-controls\">\n";
      //hart_html_output += "  <div class=\"chart-instructions\">Use mouse wheel to zoom, click and drag to move</div>\n";
      chart_html_output += "  <button id=\"resetZoomBtn\" class=\"reset-zoom-btn\">Сбросить масштаб</button>\n";
      chart_html_output += "</div>\n";
      
   
       // Build Chart.js HTML structure with modern dark theme
       chart_html_output += "<div class=\"chart-container\">\n";
       chart_html_output += "  <canvas id=\"symbolPnlChart\"></canvas>\n";
       chart_html_output += "</div>\n"; // Close chart-container div
   
       // Add JavaScript for Chart.js with modern formatting and interactive tooltips
       chart_html_output += "<script>\n";
       chart_html_output += "  document.addEventListener('DOMContentLoaded', function() {\n";
       chart_html_output += "    try {\n"; // Added try-catch for debugging on mobile
       chart_html_output += "      // Register the zoom plugin globally\n";
       chart_html_output += "      // Zoom plugin auto-registers with Chart.js\n";
       chart_html_output += "      console.log('Chart plugins:', Chart.defaults.plugins);\n"; // Add this debug line
       chart_html_output += "      var ctxSymbols = document.getElementById('symbolPnlChart').getContext('2d');\n";
       chart_html_output += "      window.symbolPnlChart = new Chart(ctxSymbols, {\n";
       chart_html_output += "        type: 'line',\n";
       chart_html_output += "        data: {\n";
       chart_html_output += "          labels: [" + global_labels_js_array + "],\n";
       chart_html_output += "          datasets: [" + chart_datasets_js + "]\n";
       chart_html_output += "        },\n";
       chart_html_output += "        options: {\n";
       chart_html_output += "          responsive: true,\n";
       chart_html_output += "          maintainAspectRatio: false,\n";
       chart_html_output += "          interaction: {\n";
       chart_html_output += "            mode: 'index',\n";
       chart_html_output += "            intersect: false\n";
       chart_html_output += "          },\n";
       chart_html_output += "          plugins: {\n";
       
       chart_html_output += "            zoom: {                              \n";
         chart_html_output += "              pan: {                               \n";
         chart_html_output += "                enabled: true,                     \n";
         chart_html_output += "                mode: 'xy',                        \n";
         chart_html_output += "                modifierKey: null,               \n";
         chart_html_output += "                threshold: 5,                      \n";
         chart_html_output += "                drag: { enabled: true },           \n";
         chart_html_output += "                onPanStart: function({ chart }) { chart.canvas.style.cursor = 'grabbing'; },\n";
         chart_html_output += "                onPanComplete: function({ chart }) { chart.canvas.style.cursor = 'default'; }\n";
         chart_html_output += "              },                                   \n";
         chart_html_output += "              zoom: {                              \n";
         chart_html_output += "                wheel: { enabled: true },          \n";
         chart_html_output += "                pinch: { enabled: true },          \n";
         chart_html_output += "                mode: 'xy'                        \n";
         chart_html_output += "              },                                   \n";
         chart_html_output += "              limits: { y: { min: 'original', max: 'original' } }\n";
         chart_html_output += "            },                                     \n";


      //chart_html_output += "            },\n";
       
       // Custom tooltip implementation that shows all symbols
         chart_html_output += "            tooltip: {\n";
         chart_html_output += "              enabled: false,\n";
         chart_html_output += "              external: function(context) {\n";
         chart_html_output += "                // Create custom tooltip element if it doesn't exist\n";
         chart_html_output += "                let tooltipEl = document.getElementById('chartjs-tooltip');\n";
         chart_html_output += "                \n";
         chart_html_output += "                if (!tooltipEl) {\n";
         chart_html_output += "                  tooltipEl = document.createElement('div');\n";
         chart_html_output += "                  tooltipEl.id = 'chartjs-tooltip';\n";
         chart_html_output += "                  tooltipEl.classList.add('chart-tooltip');\n";
         chart_html_output += "                  document.body.appendChild(tooltipEl);\n";
         chart_html_output += "                }\n";
         chart_html_output += "                \n";
         chart_html_output += "                // Hide if no tooltip\n";
         chart_html_output += "                const tooltipModel = context.tooltip;\n";
         chart_html_output += "                if (tooltipModel.opacity === 0) {\n";
         chart_html_output += "                  tooltipEl.style.opacity = 0;\n";
         chart_html_output += "                  return;\n";
         chart_html_output += "                }\n";
         chart_html_output += "                \n";
         chart_html_output += "                // Set tooltip content\n";
         chart_html_output += "                if (tooltipModel.body) {\n";
         chart_html_output += "                  const titleLines = tooltipModel.title || [];\n";
         chart_html_output += "                  \n";
         chart_html_output += "                  let innerHtml = '';\n";
         chart_html_output += "                  \n";
         chart_html_output += "                  // Add title\n";
         chart_html_output += "                  innerHtml += '<div style=\"margin-bottom:6px;font-size:13px;opacity:0.8;\">';\n";
         chart_html_output += "                  titleLines.forEach(function(title) {\n";
         chart_html_output += "                    innerHtml += title;\n";
         chart_html_output += "                  });\n";
         chart_html_output += "                  innerHtml += '</div>';\n";
         chart_html_output += "                  \n";
         chart_html_output += "                  // Add all symbol values\n";
         chart_html_output += "                  context.tooltip.dataPoints.forEach((dataPoint, i) => {\n";
         chart_html_output += "                    const dataset = context.chart.data.datasets[dataPoint.datasetIndex];\n";
         chart_html_output += "                    const value = dataPoint.parsed.y;\n";
         chart_html_output += "                    const formattedValue = value.toLocaleString(undefined, {\n";
         chart_html_output += "                      minimumFractionDigits: 2,\n";
         chart_html_output += "                      maximumFractionDigits: 2\n";
         chart_html_output += "                    });\n";
         chart_html_output += "                    \n";
         chart_html_output += "                    const isPositive = value >= 0;\n";
         chart_html_output += "                    const valueColor = isPositive ? '#00c853' : '#ff5252';\n";
         chart_html_output += "                    const valuePrefix = isPositive ? '+' : '';\n";
         chart_html_output += "                    \n";
         chart_html_output += "                    innerHtml += `<div class=\"tooltip-symbol\">\n";
         chart_html_output += "                      <div class=\"tooltip-color\" style=\"background-color:${dataset.borderColor}\"></div>\n";
         chart_html_output += "                      <div class=\"tooltip-label\">${dataset.label}</div>\n";
         chart_html_output += "                      <div class=\"tooltip-value\" style=\"color:${valueColor}\">${valuePrefix}${formattedValue}</div>\n";
         chart_html_output += "                    </div>`;\n";
         chart_html_output += "                  });\n";
         chart_html_output += "                  \n";
         chart_html_output += "                  tooltipEl.innerHTML = innerHtml;\n";
         chart_html_output += "                }\n";
         chart_html_output += "                \n";
         chart_html_output += "                // Display, position, and set styles for tooltip\n";
         chart_html_output += "                tooltipEl.style.opacity = 1;\n";
         chart_html_output += "                tooltipEl.style.position = 'absolute';\n";
         chart_html_output += "                tooltipEl.style.pointerEvents = 'none';\n";
         chart_html_output += "                \n";
         chart_html_output += "                const position = context.chart.canvas.getBoundingClientRect();\n";
         chart_html_output += "                const canvasRight = position.right + window.pageXOffset;\n";
         chart_html_output += "                \n";
         chart_html_output += "                // Position tooltip consistently to the right of cursor\n";
         chart_html_output += "                const tooltipX = position.left + window.pageXOffset + tooltipModel.caretX + 15; // 15px offset from cursor\n";
         chart_html_output += "                const tooltipY = position.top + window.pageYOffset + tooltipModel.caretY;\n";
         chart_html_output += "                \n";
         chart_html_output += "                // Check if tooltip would go off right edge of screen\n";
         chart_html_output += "                const tooltipWidth = 240; // Approximate width of tooltip\n";
         chart_html_output += "                if (tooltipX + tooltipWidth > window.innerWidth + window.pageXOffset) {\n";
         chart_html_output += "                  // Place to the left of cursor instead\n";
         chart_html_output += "                  tooltipEl.style.left = (tooltipX - tooltipWidth - 30) + 'px';\n";
         chart_html_output += "                } else {\n";
         chart_html_output += "                  tooltipEl.style.left = tooltipX + 'px';\n";
         chart_html_output += "                }\n";
         chart_html_output += "                \n";
         chart_html_output += "                tooltipEl.style.top = tooltipY + 'px';\n";
         chart_html_output += "                tooltipEl.style.transform = 'translateY(-50%)';\n";
         chart_html_output += "                \n";
         chart_html_output += "                // Add event listeners for mouse enter/leave\n";
         chart_html_output += "                const chartCanvas = context.chart.canvas;\n";
         chart_html_output += "                \n";
         chart_html_output += "                chartCanvas.onmouseout = function() {\n";
         chart_html_output += "                  tooltipEl.style.opacity = 0;\n";
         chart_html_output += "                };\n";
         chart_html_output += "                \n";
         chart_html_output += "                chartCanvas.onmouseover = function() {\n";
         chart_html_output += "                  if (context.tooltip.opacity !== 0) {\n";
         chart_html_output += "                    tooltipEl.style.opacity = 1;\n";
         chart_html_output += "                  }\n";
         chart_html_output += "                };\n";
         chart_html_output += "              }\n"; // This closes the external function
         chart_html_output += "            },\n";
       
       chart_html_output += "            legend: {\n";
       chart_html_output += "              position: 'bottom',\n";
       chart_html_output += "              labels: {\n";
       chart_html_output += "                color: '#e0e0e0',\n";
       chart_html_output += "                padding: 15,\n";
       chart_html_output += "                usePointStyle: true,\n";
       chart_html_output += "                pointStyleWidth: 10,\n";
       chart_html_output += "                font: {\n";
       chart_html_output += "                  family: 'Segoe UI, system-ui, sans-serif'\n";
       chart_html_output += "                }\n";
       chart_html_output += "              }\n";
       chart_html_output += "            }\n";
       chart_html_output += "          },\n";
       chart_html_output += "          scales: {\n";
       chart_html_output += "            x: {\n";
       chart_html_output += "              grid: {\n";
       chart_html_output += "                display: false\n"; // Remove gridlines
       chart_html_output += "              },\n";
       chart_html_output += "              ticks: {\n";
       chart_html_output += "                color: '#a0a0a0',\n";
       chart_html_output += "                maxRotation: 0,\n";
       chart_html_output += "                autoSkip: true,\n";
       chart_html_output += "                maxTicksLimit: 6\n"; // Show fewer dates
       chart_html_output += "              }\n";
       chart_html_output += "            },\n";
       chart_html_output += "            y: {\n";
       chart_html_output += "              grid: {\n";
       chart_html_output += "                display: false\n"; // Remove gridlines
       chart_html_output += "              },\n";
       chart_html_output += "              ticks: {\n";
       chart_html_output += "                color: '#a0a0a0'\n";
       chart_html_output += "              }\n";
       chart_html_output += "            }\n";
       chart_html_output += "          }\n";
       chart_html_output += "        }\n";
       chart_html_output += "      });\n";
       
       // Add reset zoom button event handler
       chart_html_output += "      document.getElementById('resetZoomBtn').addEventListener('click', function() {\n";
       chart_html_output += "        symbolPnlChart.resetZoom();\n";
       chart_html_output += "      });\n";
       chart_html_output += "      console.log('Pan config:', window.symbolPnlChart.options.plugins.zoom.pan);\n";

       
       chart_html_output += "    } catch (e) { console.error('Error initializing symbol PnL chart:', e); }\n"; // Catch errors
       chart_html_output += "  });\n";
       chart_html_output += "</script>\n";
    
       return chart_html_output;
   }

   class CSymbolStats : public CObject
   {
   public:
       string    symbolName;         // Имя символа / Symbol name
       double    totalNetPL;         // Общий чистый P/L (с учетом комиссий и свопов) / Total net P/L
       int       winCount;           // Количество прибыльных сделок / Number of winning deals
       int       lossCount;          // Количество убыточных сделок / Number of losing deals
       double    totalGrossProfit;   // Сумма всех положительных P/L сделок / Sum of all positive deal P/L
       double    totalGrossLoss;     // Сумма модулей всех отрицательных P/L сделок / Sum of absolute values of all negative deal P/L
       int       totalDeals;         // Общее количество торговых сделок (Buy/Sell) / Total number of trading deals
       
       double    totalCommission;    // Общая комиссия по символу / Total commission for the symbol
       double    totalSwap;          // Общий своп по символу / Total swap for the symbol
       double    totalFees;          // Общие издержки (комиссия + своп) / Total fees (commission + swap)

       double    winRatePercent;     // Процент прибыльных сделок / Win rate percentage
       double    avgWin;             // Средняя прибыльная сделка / Average winning deal
       double    avgLoss;            // Средняя убыточная сделка (положительное число) / Average losing deal
       double    profitFactor;       // Профит-фактор / Profit factor

       CSymbolStats(string name = "") : symbolName(name),
                                         totalNetPL(0),
                                         winCount(0),
                                         lossCount(0),
                                         totalGrossProfit(0),
                                         totalGrossLoss(0),
                                         totalDeals(0),
                                         totalCommission(0),
                                         totalSwap(0),
                                         totalFees(0),
                                         winRatePercent(0),
                                         avgWin(0),
                                         avgLoss(0),
                                         profitFactor(0)
       {}

       void Update(double pl, double commission, double swap) { 
           totalDeals++; 
           double currentDealNetPL = pl + commission + swap; 
           totalNetPL += currentDealNetPL; 
           
           totalCommission += commission;
           totalSwap += swap;
           totalFees += commission + swap; 

           if (currentDealNetPL > 0) { 
               winCount++;
               totalGrossProfit += currentDealNetPL; 
           } else if (currentDealNetPL < 0) {
               lossCount++;
               totalGrossLoss += MathAbs(currentDealNetPL); 
           }
       }

       void CalculateDerivedStats() {
           if (totalDeals > 0) {
               winRatePercent = NormalizeDouble((double)winCount / totalDeals * 100.0, 1); 
           } else {
               winRatePercent = 0;
           }
           avgWin = (winCount > 0) ? NormalizeDouble(totalGrossProfit / winCount, 2) : 0;
           avgLoss = (lossCount > 0) ? NormalizeDouble(totalGrossLoss / lossCount, 2) : 0; 
           if (totalGrossLoss > 0) {
               profitFactor = NormalizeDouble(totalGrossProfit / totalGrossLoss, 2);
           } else if (totalGrossProfit > 0 && lossCount == 0) { 
               profitFactor = -1; 
           } else { 
               profitFactor = 0;
           }
       }
       
       virtual int Compare(const CObject *node, const int mode = 0) const override {
            const CSymbolStats *other = (const CSymbolStats *)node;
            return StringCompare(symbolName, other.symbolName);
       }
   };    
   
   string GetSymbolStatsHTMLTable(datetime startTime, datetime endTime)
   {
       Print(__FUNCTION__, ": Расчет статистики по символам за период [", TimeToString(startTime, TIME_DATE), " - ", TimeToString(endTime, TIME_DATE), "]");
       string htmlResult = "<h3>Статистика по инструментам</h3>\n"; 
   
       if (!HistorySelect(startTime, endTime)) {
           Print(__FUNCTION__, ": Ошибка выбора истории.");
           return htmlResult + "<div class=\"empty-section-message\">Ошибка получения истории сделок для статистики по символам.</div>";
       }
   
       int totalDealsInPeriod = HistoryDealsTotal(); 
       if (totalDealsInPeriod == 0) {
           return htmlResult + "<div class=\"empty-section-message\">Нет сделок за указанный период для анализа по символам.</div>"; 
       }
   
       CArrayObj symbolStatsList;     
       // CArrayString uniqueSymbolNames; // Эта переменная не используется. Если не нужна, можно удалить.
   
       int tradeDealsCount = 0; 
   
       for (int i = 0; i < totalDealsInPeriod; i++) {
           ulong dealTicket = HistoryDealGetTicket(i);
           if (dealTicket == 0) continue; 
   
           ENUM_DEAL_TYPE dealType = (ENUM_DEAL_TYPE)HistoryDealGetInteger(dealTicket, DEAL_TYPE);
           if (dealType != DEAL_TYPE_BUY && dealType != DEAL_TYPE_SELL) continue; 
   
           tradeDealsCount++; 
   
           string dealSymbol = HistoryDealGetString(dealTicket, DEAL_SYMBOL);
           double profit = HistoryDealGetDouble(dealTicket, DEAL_PROFIT);
           double commission = HistoryDealGetDouble(dealTicket, DEAL_COMMISSION);
           double swap = HistoryDealGetDouble(dealTicket, DEAL_SWAP);
       
           CSymbolStats *stats = NULL; 
            bool found = false;
            for(int k=0; k < symbolStatsList.Total(); k++)
            {
                CSymbolStats *current = (CSymbolStats*)symbolStatsList.At(k);
                if(current != NULL && current.symbolName == dealSymbol)
                {
                    stats = current;
                    found = true;
                    break;
                }
            }

           if (!found) { 
               stats = new CSymbolStats(dealSymbol); 
               if (!symbolStatsList.Add(stats)) { 
                   Print(__FUNCTION__, ": Ошибка добавления статистики для символа ", dealSymbol);
                   delete stats; 
                   stats = NULL; 
               }
           }
   
           if (stats != NULL) {
               stats.Update(profit, commission, swap); 
           } else {
                Print(__FUNCTION__, ": Не удалось обработать статистику для ", dealSymbol);
           }
       } 
   
       if (symbolStatsList.Total() == 0) { 
           return htmlResult + "<div class=\"empty-section-message\">Не найдено торговых сделок (Buy/Sell) за период для статистики по символам.</div>";
       }
   
       htmlResult += "<table>\n<thead>\n<tr>\n"
                     "  <th>Символ</th>\n"         
                     "  <th>Сделок</th>\n"         
                     "  <th>Общий Net P/L</th>\n"   
                     "  <th>Профит Фактор</th>\n"   
                     "  <th>% Приб.</th>\n"         
                     "  <th>Сред. Прибыль</th>\n"   
                     "  <th>Сред. Убыток</th>\n"   
                     "</tr>\n</thead>\n<tbody>\n";
   
       symbolStatsList.Sort();
   
       for (int i = 0; i < symbolStatsList.Total(); i++) {
           CSymbolStats *stats = (CSymbolStats *)symbolStatsList.At(i); 
           if (stats == NULL) continue; 
   
           stats.CalculateDerivedStats(); 
   
           string pfStr;
           if (stats.profitFactor < 0) pfStr = "Inf"; 
           else pfStr = DoubleToString(stats.profitFactor, 2); 
           
           // Modern styling with color formatting for P/L
           string plClass = stats.totalNetPL >= 0 ? "positive" : "negative";
           string plPrefix = stats.totalNetPL >= 0 ? "+" : "";
   
           htmlResult += StringFormat(
               "<tr>\n"
               "  <td>%s</td>\n"               
               "  <td>%d</td>\n"               
               "  <td class=\"%s\">%s%.2f</td>\n"  // Added class and prefix            
               "  <td>%s</td>\n"               
               "  <td>%.1f%%</td>\n"           
               "  <td>%.2f</td>\n"             
               "  <td>%.2f</td>\n"             
               "</tr>\n",
               stats.symbolName,
               stats.totalDeals,
               plClass, plPrefix, stats.totalNetPL,
               pfStr,
               stats.winRatePercent,
               stats.avgWin,
               stats.avgLoss 
           );
       }
   
       htmlResult += "</tbody>\n</table>\n"; 
   
       symbolStatsList.FreeMode(true); // Устанавливаем FreeMode в true для удаления объектов
       symbolStatsList.Clear();    // Clear удалит указатели, FreeMode=true обеспечит вызов delete
       
       // CArrayString uniqueSymbolNames не используется для подсчета в этой версии,
       // но если бы использовалась, ее тоже нужно было бы очистить: uniqueSymbolNames.Shutdown();
       // Для подсчета уникальных символов, которые были реально обработаны (вошли в symbolStatsList),
       // можно было бы использовать symbolStatsList.Total() до Clear().
       // int processedSymbolsCount = symbolStatsList.Total(); // Если бы это было нужно здесь
       Print(__FUNCTION__, ": Статистика по символам (таблица) рассчитана."); // Убрано processedSymbolsCount, т.к. uniqueSymbolNames не заполнялась

       return htmlResult; 
   }
   

   /**
    * Вспомогательная функция: формирует строку с основными сведениями о счёте.
    * Возвращает HTML-блок (в виде строки), который потом включается в общий отчёт.
    */
   string GetAccountSummaryHTML()
   {
     // Получаем структуру AccountInfo
     AccountInfoPlus accountInfo;
     ZeroMemory(accountInfo);
     // Заполняем структуру напрямую - в MQL5 функции AccountInfo* возвращают значения
     accountInfo.balance = AccountInfoDouble(ACCOUNT_BALANCE);
     accountInfo.equity = AccountInfoDouble(ACCOUNT_EQUITY);
     accountInfo.margin = AccountInfoDouble(ACCOUNT_MARGIN);
     accountInfo.margin_free = AccountInfoDouble(ACCOUNT_FREEMARGIN);
     accountInfo.login = AccountInfoInteger(ACCOUNT_LOGIN);
     // Проверяем, что мы получили действительные значения
     bool isAccInfoOk = (/*accountInfo.balance >= 0 && accountInfo.equity >= 0 &&*/ accountInfo.login > 0); // Баланс и эквити могут быть < 0 / Balance/Equity can be < 0

     // Логгируем факт получения
     Print(__FUNCTION__,": Получение информации о счёте, статус=", isAccInfoOk);

     // Если не удалось — можно прервать или вывести минимальные данные
     if(!isAccInfoOk)
     {
        // Используем assert в отладочных целях, чтобы поймать ошибку во время разработки
        // В Release-режиме это не остановит скрипт
        assert(isAccInfoOk);

        return("<div class=\"account-error\">Ошибка чтения данных счёта! (Логин не получен)</div>"); // Уточнено / Clarified
     }

     // Modern card-based layout for account info
     string html = "<h3>Сводка по счёту</h3>\n";
     html += "<div class=\"account-info\">\n";
     
     // Account number card
     html += StringFormat(
        "<div class=\"info-item\">\n"
        "  <div class=\"label\">Номер счёта</div>\n"
        "  <div class=\"value\">%I64d</div>\n"
        "</div>\n",
        accountInfo.login
     );
     
     // Balance card
     html += StringFormat(
        "<div class=\"info-item\">\n"
        "  <div class=\"label\">Текущий баланс</div>\n"
        "  <div class=\"value\">%.2f</div>\n"
        "</div>\n",
        accountInfo.balance
     );
     
     // Equity card
     html += StringFormat(
        "<div class=\"info-item\">\n"
        "  <div class=\"label\">Текущее equity</div>\n"
        "  <div class=\"value\">%.2f</div>\n"
        "</div>\n",
        accountInfo.equity
     );
     
     // Margin used card
     html += StringFormat(
        "<div class=\"info-item\">\n"
        "  <div class=\"label\">Используемая маржа</div>\n"
        "  <div class=\"value\">%.2f</div>\n"
        "</div>\n",
        accountInfo.margin
     );
     
     // Free margin card
     html += StringFormat(
        "<div class=\"info-item\">\n"
        "  <div class=\"label\">Свободная маржа</div>\n"
        "  <div class=\"value\">%.2f</div>\n"
        "</div>\n",
        accountInfo.margin_free
     );
     
     html += "</div>\n"; // Close account-info div

     return html;
   }

   /**
    * Функция собирает список сделок из истории, формирует таблицу (HTML), возвращает её в виде строки.
    * @param fromDate Начальная дата для истории / Start date for history
    * @param toDate Конечная дата для истории / End date for history
    * @return Строка с HTML-таблицей сделок / String with HTML table of deals
    */
   string GetDealsHistoryHTML(datetime fromDate, datetime toDate) // Добавлены параметры периода / Added period parameters
   {
     // Применяем выборку истории для ЗАДАННОГО периода
     // Apply history selection for the SPECIFIED period
     bool historySelected = HistorySelect(fromDate, toDate);
     Print(__FUNCTION__,": История выбрана (", historySelected, ") за период с ", TimeToString(fromDate), " по ", TimeToString(toDate));

     // Подготовим заголовок таблицы
     // Prepare table header
     string htmlTable =
        "<h3>Торговая история (за период)</h3>\n" // Уточнено / Clarified
        "<table>\n" // Убран border, cellspacing, cellpadding т.к. есть в CSS / Removed border, cellspacing, cellpadding as they are in CSS
        "<thead>\n" // Добавлен thead / Added thead
        "<tr>\n" // Убран bgcolor, т.к. есть в CSS / Removed bgcolor as it's in CSS
           "<th>Время</th>\n"
           "<th>Тип сделки</th>\n"
           "<th>Тикер</th>\n"
           "<th>Объём</th>\n"
           "<th>Цена</th>\n"
           "<th>Прибыль</th>\n"
           "<th>Комиссия</th>\n"
           "<th>Своп</th>\n"
        "</tr>\n"
        "</thead>\n"
        "<tbody>\n"; // Добавлен tbody / Added tbody

     // Получаем общее количество сделок в истории
     // Get the total number of deals in history
     int dealsCount = HistoryDealsTotal(); // Используем int / Use int
     Print(__FUNCTION__,": Найдено сделок в периоде=", dealsCount);

    // Если сделок нет, выводим сообщение / If no deals, display message
    if (dealsCount == 0) {
        htmlTable += "<tr><td colspan='8'><div class=\"empty-section-message\">Сделок за указанный период не найдено.</div></td></tr>\n";
    } else {
        // Перебираем все сделки
        // Iterate through all deals
        for(int i=0; i<dealsCount; i++) // Используем int / Use int
        {
            ulong dealTicket = HistoryDealGetTicket(i);
            if(dealTicket == 0)
            {
                Print(__FUNCTION__,": Пропущен dealTicket=0 на i=", i);
                continue;
            }

            // Считываем нужные данные сделки / Read necessary deal data
            ENUM_DEAL_TYPE dealType = (ENUM_DEAL_TYPE)HistoryDealGetInteger(dealTicket, DEAL_TYPE);
            string dealSymbol      = HistoryDealGetString(dealTicket, DEAL_SYMBOL);
            double dealVolume      = HistoryDealGetDouble(dealTicket, DEAL_VOLUME);
            double dealPrice       = HistoryDealGetDouble(dealTicket, DEAL_PRICE);
            double dealProfit      = HistoryDealGetDouble(dealTicket, DEAL_PROFIT);
            double dealCommission= HistoryDealGetDouble(dealTicket, DEAL_COMMISSION);
            double dealSwap        = HistoryDealGetDouble(dealTicket, DEAL_SWAP);
            datetime dealTime      = (datetime)HistoryDealGetInteger(dealTicket, DEAL_TIME);
            int price_digits = (int)SymbolInfoInteger(dealSymbol, SYMBOL_DIGITS); // Получаем точность цены / Get price digits
            if (price_digits <= 0) price_digits = 5; // Значение по умолчанию / Default value

            // Преобразуем тип сделки в человекочитаемый формат / Convert deal type to human-readable format
            string dealTypeStr;
            switch(dealType)
            {
                case DEAL_TYPE_BUY:         dealTypeStr = "Buy";         break;
                case DEAL_TYPE_SELL:        dealTypeStr = "Sell";        break;
                case DEAL_TYPE_BALANCE:     dealTypeStr = "Balance";     break;
                case DEAL_TYPE_CREDIT:      dealTypeStr = "Credit";      break;
                case DEAL_TYPE_CHARGE:      dealTypeStr = "Charge";      break;
                case DEAL_TYPE_CORRECTION:  dealTypeStr = "Correction"; break;
                case DEAL_TYPE_BONUS:       dealTypeStr = "Bonus";       break;
                case DEAL_TYPE_COMMISSION:  dealTypeStr = "Commission"; break;
                #ifdef DEAL_TYPE_CASHIN
                case DEAL_TYPE_CASHIN:      dealTypeStr = "CashIn";      break;
                #else
                case 9:                     dealTypeStr = "CashIn";      break; // DEAL_TYPE_CASHIN in newer versions
                #endif
                #ifdef DEAL_TYPE_CASHOUT
                case DEAL_TYPE_CASHOUT:     dealTypeStr = "CashOut";     break;
                #else
                case 10:                    dealTypeStr = "CashOut";     break; // DEAL_TYPE_CASHOUT in newer versions
                #endif
                default: dealTypeStr = EnumToString(dealType); // Используем EnumToString для неизвестных / Use EnumToString for unknown
            }
            
            // Add CSS classes for profit/commission/swap values
            string profitClass = dealProfit >= 0 ? "positive" : "negative";
            string commClass = dealCommission >= 0 ? "positive" : "negative";
            string swapClass = dealSwap >= 0 ? "positive" : "negative";
            
            // Format values with plus sign for positive numbers
            string profitPrefix = dealProfit > 0 ? "+" : "";
            string commPrefix = dealCommission > 0 ? "+" : "";
            string swapPrefix = dealSwap > 0 ? "+" : "";

            // Формируем строку таблицы / Format table row
            htmlTable += StringFormat(
                "<tr>\n" // Добавлены переносы / Added newlines
                "  <td>%s</td>\n"
                "  <td>%s</td>\n"
                "  <td>%s</td>\n"
                "  <td>%.2f</td>\n"
                "  <td>%s</td>\n" // Используем DoubleToString для цены / Use DoubleToString for price
                "  <td class=\"%s\">%s%.2f</td>\n" // Added class and prefix
                "  <td class=\"%s\">%s%.2f</td>\n" // Added class and prefix
                "  <td class=\"%s\">%s%.2f</td>\n" // Added class and prefix
                "</tr>\n",
                TimeToString(dealTime, TIME_DATE|TIME_SECONDS),
                dealTypeStr,
                dealSymbol,
                dealVolume,
                DoubleToString(dealPrice, price_digits), // Форматируем цену / Format price
                profitClass, profitPrefix, dealProfit,
                commClass, commPrefix, dealCommission,
                swapClass, swapPrefix, dealSwap
            );
        } // end for
    } // end else (dealsCount > 0)

     htmlTable += "</tbody>\n</table>\n"; // Закрываем tbody и table / Close tbody and table
     return htmlTable;
   }

   // Структура для хранения точки данных эквити
   // Structure to store an equity data point
   struct EquityDataPoint {
        datetime time;    // Время точки данных / Timestamp of the data point
        double   equity;  // Значение эквити в этот момент / Equity value at this moment
   };

   /**
    * Рассчитывает историю эквити на основе сделок.
    * Calculates equity history based on deals.
    *
    * @param startTime      Начальное время для расчета / Start time for calculation
    * @param endTime        Конечное время для расчета / End time for calculation
    * @param equityData     Выходной массив с точками данных эквити / Output array with equity data points
    * @param initialEquity Начальное значение эквити (может быть приближенным) / Initial equity value (can be approximate)
    * @return               true, если расчет успешен, иначе false / true if calculation is successful, false otherwise
    */
   bool GetEquityCurveData(datetime startTime, datetime endTime, EquityDataPoint &equityData[], double &initialEquity)
   {
        ArrayFree(equityData); // Очищаем выходной массив / Clear the output array

        // === Определение начального эквити (Упрощенный вариант) ===
        // === Determining Initial Equity (Simplified version) ===
      // Выбираем ВСЮ историю до КОНЦА периода отчета, чтобы вычесть профит / Select ALL history up to the END of the report period to subtract profit
        if (!HistorySelect(0, endTime))
        {
            Print(__FUNCTION__, ": Ошибка выбора всей истории до ", TimeToString(endTime), " для расчета начального эквити.");
            return false;
        }

        double totalNetProfitInPeriod = 0;
        int totalDealsBeforeEnd = HistoryDealsTotal();
      bool periodHasDeals = false; // Флаг, были ли сделки в периоде / Flag if deals occurred in period

        for(int i = 0; i < totalDealsBeforeEnd; i++)
        {
            ulong dealTicket = HistoryDealGetTicket(i);
            if (dealTicket == 0) continue;
            datetime dealTime = (datetime)HistoryDealGetInteger(dealTicket, DEAL_TIME);
            // Суммируем только сделки ВНУТРИ интересующего нас периода / Sum only deals WITHIN our period of interest
            if (dealTime >= startTime && dealTime <= endTime)
            {
              periodHasDeals = true; // Нашли хотя бы одну сделку в периоде / Found at least one deal in the period
                // Учитываем профит, комиссию и своп / Consider profit, commission, and swap
                totalNetProfitInPeriod += HistoryDealGetDouble(dealTicket, DEAL_PROFIT);
                totalNetProfitInPeriod += HistoryDealGetDouble(dealTicket, DEAL_COMMISSION);
                totalNetProfitInPeriod += HistoryDealGetDouble(dealTicket, DEAL_SWAP);
              // TODO: Учет балансовых операций / Consider balance operations
            }
        }
        // Приблизительное начальное эквити = Текущее эквити - Чистый профит за период / Approx initial equity = Current equity - Net profit for the period
        initialEquity = AccountInfoDouble(ACCOUNT_EQUITY) - totalNetProfitInPeriod;

      // Если в периоде сделок не было, начальное эквити равно текущему / If no deals in period, initial equity equals current
      if (!periodHasDeals) {
            initialEquity = AccountInfoDouble(ACCOUNT_EQUITY);
            Print(__FUNCTION__, ": Сделок в периоде не найдено. Начальное эквити = Текущее = ", DoubleToString(initialEquity, 2));
      } else {
            Print(__FUNCTION__, ": Расчетное начальное эквити = ", DoubleToString(initialEquity, 2));
      }

        // === Перерасчет истории для построения кривой ===
        // === Recalculating history to build the curve ===
        if (!HistorySelect(startTime, endTime)) // Выбираем историю ТОЛЬКО для нужного периода / Select history ONLY for the desired period
        {
            Print(__FUNCTION__, ": Ошибка выбора истории для периода [", TimeToString(startTime), " - ", TimeToString(endTime), "]");
            return false;
        }

        int dealsInPeriod = HistoryDealsTotal(); // Количество сделок в выбранном периоде / Number of deals in the selected period
        ArrayResize(equityData, dealsInPeriod + 1); // +1 для начальной точки / +1 for the initial point
        int pointIndex = 0; // Индекс для записи в массив / Index for writing to the array

        // Добавляем начальную точку / Add the initial point
        equityData[pointIndex].time = startTime;
        equityData[pointIndex].equity = NormalizeDouble(initialEquity, 2); // Нормализуем начальное / Normalize initial
        pointIndex++;

        double currentEquity = initialEquity; // Текущее значение для расчета / Current value for calculation
        // Проходим по сделкам ВНУТРИ периода / Iterate through deals WITHIN the period
        for (int i = 0; i < dealsInPeriod; i++)
        {
            ulong dealTicket = HistoryDealGetTicket(i);
            if (dealTicket == 0) continue;

            // Учитываем финансовый результат сделки / Consider the financial result of the deal
            double profit = HistoryDealGetDouble(dealTicket, DEAL_PROFIT);
            double commission = HistoryDealGetDouble(dealTicket, DEAL_COMMISSION);
            double swap = HistoryDealGetDouble(dealTicket, DEAL_SWAP);
            // TODO: Учет балансовых операций / Consider balance operations

            currentEquity += profit + commission + swap; // Обновляем эквити / Update equity

            datetime dealTime = (datetime)HistoryDealGetInteger(dealTicket, DEAL_TIME);

            // Сохраняем точку данных / Store the data point
            if(pointIndex < dealsInPeriod + 1) // Проверка границы массива / Array boundary check
            {
                 equityData[pointIndex].time = dealTime;
                 // Округляем эквити до 2 знаков / Round equity to 2 decimal places
                 equityData[pointIndex].equity = NormalizeDouble(currentEquity, 2);
                 pointIndex++;
            } else {
                 Print(__FUNCTION__, ": Предупреждение: Достигнут лимит точек массива эквити!");
                 break;
            }
        }
        // Обрезаем массив до фактического числа точек / Trim the array to the actual number of points
        ArrayResize(equityData, pointIndex);
        Print(__FUNCTION__, ": Сформировано ", pointIndex, " точек данных эквити.");
        return (pointIndex > 1); // Успех, если есть хотя бы начальная и еще одна точка / Success if there's at least the initial point and one more
   }

   /**
    * Форматирует данные эквити в строки JavaScript-массивов для Chart.js.
    * Formats equity data into JavaScript array strings for Chart.js.
    *
    * @param equityData    Массив с точками данных / Array with data points
    * @param outJsLabels   Выходная строка с метками времени (формат JS) / Output string with time labels (JS format)
    * @param outJsData     Выходная строка со значениями эквити (формат JS) / Output string with equity values (JS format)
    * @return              true, если форматирование успешно / true if formatting is successful
    */
   bool FormatEquityDataForJS(EquityDataPoint &equityData[], string &outJsLabels, string &outJsData)
   {
        outJsLabels = ""; // Инициализируем пустой строкой / Initialize with empty string
        outJsData = "";    // Инициализируем пустой строкой / Initialize with empty string
        int totalPoints = ArraySize(equityData);

        if(totalPoints == 0) {
          Print(__FUNCTION__, ": Нет данных для форматирования в JS.");
          return false; // Нет данных для форматирования / No data to format
      }

        // Собираем строки для JavaScript / Assemble strings for JavaScript
        for(int i = 0; i < totalPoints; i++)
        {
            // Форматируем метку времени в виде 'ГГГГ-ММ-ДД ЧЧ:ММ' / Format timestamp as 'YYYY-MM-DD HH:MM'
            string label = "'" + TimeToString(equityData[i].time, TIME_DATE | TIME_MINUTES) + "'";
            // Форматируем значение эквити до 2 знаков после запятой / Format equity value to 2 decimal places
            string value = DoubleToString(equityData[i].equity, 2);

            // Добавляем запятую перед элементами, кроме первого / Add comma before elements except the first one
            if(i > 0) {
                 outJsLabels += ",";
                 outJsData += ",";
            }
            outJsLabels += label; // Добавляем метку / Add label
            outJsData += value;    // Добавляем значение / Add value
        }
      Print(__FUNCTION__, ": Данные эквити успешно сформатированы для JS.");
        return true;
   }

   /**
     * Основная функция: формирует HTML-отчёт с графиком эквити и сохраняет его.
     * Main function: generates an HTML report with an equity chart and saves it.
     *
     * @param fileName Имя файла для сохранения отчета / Filename to save the report
     * @return         true при успехе, false в случае ошибки / true on success, false on error
     */
   
   bool ToFile(const string fileName)
    {
        Print(__FUNCTION__,": Начало формирования отчёта с графиком в файл=", fileName);
        datetime reportEndTime = TimeCurrent();
        datetime reportStartTime;
        MqlDateTime dt_end; TimeToStruct(reportEndTime, dt_end);
        MqlDateTime dt_start = dt_end;
        dt_start.year -= 1; 
        int startYear = dt_start.year; 
        bool isStartYearLeap = (startYear % 4 == 0 && startYear % 100 != 0) || (startYear % 400 == 0);
        if (dt_end.mon == 2 && dt_end.day == 29 && !isStartYearLeap) dt_start.day = 28;
        reportStartTime = StructToTime(dt_start);
        Print(__FUNCTION__,": Период отчета: ", TimeToString(reportStartTime, TIME_DATE), " - ", TimeToString(reportEndTime, TIME_DATE));

        // Modern dark theme styling with CSS Grid for layout
        string htmlHeader =
   "<!DOCTYPE html>\n"
   "<html>\n<head>\n"
   "<meta charset=\"UTF-8\">\n" 
   "<meta name=\"viewport\" content=\"width=device-width, initial-scale=1.0\">\n"
   "<title>MT5 Торговый Отчет</title>\n"
   "<style>\n"
   "  :root {\n"
   "    /* Dark mode color palette */\n"
   "    --bg-primary: #121212;\n"
   "    --bg-secondary: #1e1e1e;\n"
   "    --bg-card: #252525;\n"
   "    --text-primary: #e0e0e0;\n"
   "    --text-secondary: #a0a0a0;\n"
   "    --border-color: #333;\n"
   "    --accent-color: #4f8df5;\n"
   "    --accent-color-transparent: rgba(79, 141, 245, 0.2);\n"
   "    --success-color: #00c853;\n"
   "    --danger-color: #ff5252;\n"
   "  }\n"
   "  \n"
   "  body {\n"
   "    font-family: 'Segoe UI', system-ui, -apple-system, sans-serif;\n"
   "    background-color: var(--bg-primary);\n"
   "    color: var(--text-primary);\n"
   "    padding: 20px;\n"
   "    margin: 0;\n"
   "    line-height: 1.5;\n"
   "  }\n"
   "  \n"
   "  /* Typography */\n"
   "  h1, h2, h3 {\n"
   "    margin-bottom: 0.5em;\n"
   "    margin-top: 1.5em;\n"
   "    color: var(--text-primary);\n"
   "    font-weight: 300;\n"
   "  }\n"
   "  \n"
   "  h1 {\n"
   "    text-align: center;\n"
   "    font-size: 2.2rem;\n"
   "    letter-spacing: 0.5px;\n"
   "  }\n"
   "  \n"
   "  h2 {\n"
   "    font-size: 1.5rem;\n"
   "    border-bottom: 1px solid var(--border-color);\n"
   "    padding-bottom: 10px;\n"
   "  }\n"
   "  \n"
   "  h3 {\n"
   "    font-size: 1.3rem;\n"
   "    color: var(--accent-color);\n"
   "  }\n"
   "  \n"
   "  /* Card container for sections */\n"
   "  .card {\n"
   "    background-color: var(--bg-secondary);\n"
   "    border-radius: 8px;\n"
   "    box-shadow: 0 4px 20px rgba(0, 0, 0, 0.15);\n"
   "    padding: 20px;\n"
   "    margin-bottom: 25px;\n"
   "  }\n"
   "  \n"
   "  /* Account info */\n"
   "  .account-info {\n"
   "    display: grid;\n"
   "    grid-template-columns: repeat(auto-fit, minmax(200px, 1fr));\n"
   "    gap: 20px;\n"
   "  }\n"
   "  \n"
   "  .info-item {\n"
   "    padding: 15px;\n"
   "    background-color: var(--bg-card);\n"
   "    border-radius: 6px;\n"
   "  }\n"
   "  \n"
   "  .info-item .label {\n"
   "    font-size: 0.9rem;\n"
   "    color: var(--text-secondary);\n"
   "    margin-bottom: 5px;\n"
   "  }\n"
   "  \n"
   "  .info-item .value {\n"
   "    font-size: 1.3rem;\n"
   "    font-weight: 500;\n"
   "  }\n"
   "  \n"
   "  /* Tables */\n"
   "  table {\n"
   "    border-collapse: collapse;\n"
   "    margin-top: 1em;\n"
   "    font-size: 0.9em;\n"
   "    width: 100%;\n"
   "    border-radius: 8px;\n"
   "    overflow: hidden;\n"
   "  }\n"
   "  \n"
   "  th, td {\n"
   "    padding: 12px 15px;\n"
   "    text-align: left;\n"
   "    border-bottom: 1px solid var(--border-color);\n"
   "  }\n"
   "  \n"
   "  th {\n"
   "    background-color: var(--bg-card);\n"
   "    color: var(--accent-color);\n"
   "    font-weight: 500;\n"
   "    text-transform: uppercase;\n"
   "    font-size: 0.8em;\n"
   "    letter-spacing: 0.5px;\n"
   "  }\n"
   "  \n"
   "  tr:last-child td {\n"
   "    border-bottom: none;\n"
   "  }\n"
   "  \n"
   "  tr:hover {\n"
   "    background-color: rgba(255, 255, 255, 0.03);\n"
   "  }\n"
   "  \n"
   "  /* Charts */\n"
   "  .chart-container {\n"
   "    background-color: var(--bg-secondary);\n"
   "    border-radius: 8px;\n"
   "    padding: 20px;\n"
   "    margin: 20px 0;\n"
   "    box-shadow: 0 4px 20px rgba(0, 0, 0, 0.15);\n"
   "    position: relative;\n"
   "    min-height: 350px;\n"
   "  }\n"
   "  \n"
   "  .chart-container canvas {\n"
   "    width: 100% !important;\n"
   "    height: 350px !important;\n"
   "  }\n"
   "  \n"
   "  /* Positive/Negative values */\n"
   "  .positive {\n"
   "    color: var(--success-color);\n"
   "  }\n"
   "  \n"
   "  .negative {\n"
   "    color: var(--danger-color);\n"
   "  }\n"
   "  \n"
   "  /* Custom tooltip styling */\n"
   "  .chart-tooltip {\n"
   "    background-color: rgba(30, 30, 30, 0.85) !important;\n"
   "    backdrop-filter: blur(4px);\n"
   "    border-radius: 8px !important;\n"
   "    color: #fff !important;\n"
   "    border: 1px solid var(--border-color) !important;\n"
   "    font-family: 'Segoe UI', system-ui, sans-serif !important;\n"
   "    padding: 10px !important;\n"
   "    box-shadow: 0 4px 8px rgba(0, 0, 0, 0.2) !important;\n"
   "    max-width: 240px !important;\n"
   "    z-index: 1000;\n"
   "    transition: opacity 0.15s ease !important;\n"
   "    opacity: 0;\n"
   "  }\n"
   "  \n"
   "  .tooltip-symbol {\n"
   "    display: flex;\n"
   "    align-items: center;\n"
   "    margin-bottom: 3px;\n"
   "  }\n"
   "  \n"
   "  .tooltip-color {\n"
   "    width: 8px;\n"
   "    height: 8px;\n"
   "    margin-right: 8px;\n"
   "    border-radius: 50%;\n"
   "  }\n"
   "  \n"
   "  .tooltip-label {\n"
   "    font-weight: 500;\n"
   "    margin-right: 10px;\n"
   "  }\n"
   "  \n"
   "  .tooltip-value {\n"
   "    margin-left: auto;\n"
   "    font-weight: 600;\n"
   "  }\n"
   "  \n"
   "  .empty-chart-message, .empty-section-message, .account-error {\n"
   "    text-align: center;\n"
   "    padding: 20px;\n"
   "    color: var(--text-secondary);\n"
   "    font-style: italic;\n"
   "  }\n"
   "  \n"
   "  .account-error {\n"
   "    color: var(--danger-color);\n"
   "    font-weight: bold;\n"
   "  }\n"
   "  \n"
   "  /* Responsive design */\n"
   "  @media (max-width: 768px) {\n"
   "    body {\n"
   "      padding: 10px;\n"
   "    }\n"
   "    \n"
   "    .card {\n"
   "      padding: 15px;\n"
   "    }\n"
   "    \n"
   "    .account-info {\n"
   "      grid-template-columns: 1fr;\n"
   "    }\n"
   "    \n"
   "    th, td {\n"
   "      padding: 8px 10px;\n"
   "    }\n"
   "  }\n"
   "  .empty-chart-message, .empty-section-message, .account-error {\n"
   "    text-align: center;\n"
   "    padding: 20px;\n"
   "    color: var(--text-secondary);\n"
   "    font-style: italic;\n"
   "  }\n"
   "  \n"
   "  .account-error {\n"
   "    color: var(--danger-color);\n"
   "    font-weight: bold;\n"
   "  }\n"
   "  \n"
   "  /* Responsive design */\n"
   "  @media (max-width: 768px) {\n"
   "    body {\n"
   "      padding: 10px;\n"
   "    }\n"
   "    \n"
   "    .card {\n"
   "      padding: 15px;\n"
   "    }\n"
   "    \n"
   "    .account-info {\n"
   "      grid-template-columns: 1fr;\n"
   "    }\n"
   "    \n"
   "    th, td {\n"
   "      padding: 8px 10px;\n"
   "    }\n"
   "  }\n"
   "  .chart-controls {\n"
   "    display: flex;\n"
   "    justify-content: flex-end;\n"
   "    margin-bottom: 10px;\n"
   "  }\n"
   "  \n"
   "  .reset-zoom-btn {\n"
   "    background-color: var(--accent-color);\n"
   "    color: white;\n"
   "    border: none;\n"
   "    border-radius: 4px;\n"
   "    padding: 6px 12px;\n"
   "    cursor: pointer;\n"
   "    font-size: 0.9rem;\n"
   "  }\n"
   "  \n"
   "  .reset-zoom-btn:hover {\n"
   "    background-color: #3a7ad5;\n"
   "  }\n"
   "  \n"
   "  .chart-instructions {\n"
   "    font-size: 0.85rem;\n"
   "    color: var(--text-secondary);\n"
   "    margin-right: auto;\n"
   "    padding: 4px 0;\n"
   "  }\n"
   "  .chart-controls {\n"
   "    display: flex;\n"
   "    justify-content: flex-end;\n"
   "    margin-bottom: 10px;\n"
   "  }\n"
   "  \n"
   "  .reset-zoom-btn {\n"
   "    background-color: var(--accent-color);\n"
   "    color: white;\n"
   "    border: none;\n"
   "    border-radius: 4px;\n"
   "    padding: 6px 12px;\n"
   "    cursor: pointer;\n"
   "    font-size: 0.9rem;\n"
   "  }\n"
   "  \n"
   "  .reset-zoom-btn:hover {\n"
   "    background-color: #3a7ad5;\n"
   "  }\n"
   "  \n"
   "  .chart-instructions {\n"
   "    font-size: 0.85rem;\n"
   "    color: var(--text-secondary);\n"
   "    margin-right: auto;\n"
   "    padding: 4px 0;\n"
   "  }\n"
   "</style>\n"
   "<script src=\"https://cdn.jsdelivr.net/npm/chart.js@3.9.1/dist/chart.min.js\"></script>\n"
   "<script src=\"https://cdn.jsdelivr.net/npm/chartjs-plugin-zoom@1.2.1/dist/chartjs-plugin-zoom.min.js\"></script>\n"
   "</head>\n<body>\n"
   "<h1>Торговый Отчет</h1>\n"
   "<h2>Период: " + TimeToString(reportStartTime, TIME_DATE) + " - " + TimeToString(reportEndTime, TIME_DATE) + "</h2>\n";
   
        // Wrap each section in a card div
        string accountSection = "<div class=\"card\">\n" + GetAccountSummaryHTML() + "</div>\n"; 
        string equityChartSection = ""; 
        EquityDataPoint equityPoints[];
        double startEq = 0;

        if (GetEquityCurveData(reportStartTime, reportEndTime, equityPoints, startEq) && ArraySize(equityPoints) > 1) 
        {
            string jsLabels = ""; 
            string jsData = "";    
            if (FormatEquityDataForJS(equityPoints, jsLabels, jsData))
            {
                equityChartSection = "<div class=\"card\">\n";
                equityChartSection += "<h3>График эквити</h3>\n";
                equityChartSection += "<div class=\"chart-container\">\n";
                equityChartSection += "  <canvas id=\"equityChart\"></canvas>\n";
                equityChartSection += "</div>\n"; // Close chart-container div
                equityChartSection += "</div>\n"; // Close card div

                // Add JavaScript for Chart.js with modern formatting and gradient fill
                equityChartSection += "<script>\n";
                equityChartSection += "  document.addEventListener('DOMContentLoaded', function() {\n";
                equityChartSection += "    try {\n"; // Added try-catch for debugging on mobile
                equityChartSection += "      var ctxEquity = document.getElementById('equityChart').getContext('2d');\n";
                
                // Create gradient for the equity chart fill
                equityChartSection += "      var gradientFill = ctxEquity.createLinearGradient(0, 0, 0, 350);\n";
                equityChartSection += "      gradientFill.addColorStop(0, 'rgba(79, 141, 245, 0.4)');\n";
                equityChartSection += "      gradientFill.addColorStop(1, 'rgba(79, 141, 245, 0.0)');\n";
                
                equityChartSection += "      var equityChart = new Chart(ctxEquity, {\n";
                equityChartSection += "        type: 'line',\n";
                equityChartSection += "        data: {\n";
                equityChartSection += "          labels: [" + jsLabels + "],\n";
                equityChartSection += "          datasets: [{\n";
                equityChartSection += "            label: 'Equity',\n";
                equityChartSection += "            data: [" + jsData + "],\n";
                equityChartSection += "            borderColor: '#4f8df5',\n";
                equityChartSection += "            backgroundColor: gradientFill,\n"; // Use gradient fill
                equityChartSection += "            fill: true,\n"; // Fill area under the curve
                equityChartSection += "            tension: 0.2,\n"; // Smoother curve
                equityChartSection += "            pointRadius: 3,\n";
                equityChartSection += "            pointHoverRadius: 6,\n";
                equityChartSection += "            borderWidth: 1.0\n"; // Thinner line as requested
                equityChartSection += "          }]\n";
                equityChartSection += "        },\n";
                equityChartSection += "        options: {\n";
                equityChartSection += "          responsive: true,\n";
                equityChartSection += "          maintainAspectRatio: false,\n"; // Allow custom size
                equityChartSection += "          interaction: {\n";
                equityChartSection += "            mode: 'index',\n";
                equityChartSection += "            intersect: false\n";
                equityChartSection += "          },\n";
                equityChartSection += "          plugins: {\n";
                equityChartSection += "            tooltip: {\n";
                equityChartSection += "              enabled: true,\n";
                equityChartSection += "              backgroundColor: 'rgba(30, 30, 30, 0.85)',\n";
                equityChartSection += "              titleColor: '#fff',\n";
                equityChartSection += "              bodyColor: '#fff',\n";
                equityChartSection += "              borderColor: '#333',\n";
                equityChartSection += "              borderWidth: 1,\n";
                equityChartSection += "              padding: 10,\n";
                equityChartSection += "              displayColors: false,\n";
                equityChartSection += "              callbacks: {\n";
                equityChartSection += "                label: function(context) {\n";
                equityChartSection += "                  return 'Equity: ' + context.parsed.y.toLocaleString();\n";
                equityChartSection += "                }\n";
                equityChartSection += "              }\n";
                equityChartSection += "            },\n";
                equityChartSection += "            legend: {\n";
                equityChartSection += "              display: false\n"; // Hide legend as there's only one dataset
                equityChartSection += "            }\n";
                equityChartSection += "          },\n";
                equityChartSection += "          scales: {\n";
                equityChartSection += "            x: {\n";
                equityChartSection += "              grid: {\n";
                equityChartSection += "                display: false\n"; // Remove gridlines
                equityChartSection += "              },\n";
                equityChartSection += "              ticks: {\n";
                equityChartSection += "                color: '#a0a0a0',\n";
                equityChartSection += "                maxRotation: 0,\n";
                equityChartSection += "                autoSkip: true,\n";
                equityChartSection += "                maxTicksLimit: 6\n"; // Show fewer dates
                equityChartSection += "              }\n";
                equityChartSection += "            },\n";
                equityChartSection += "            y: {\n";
                equityChartSection += "              grid: {\n";
                equityChartSection += "                display: false\n"; // Remove gridlines
                equityChartSection += "              },\n";
                equityChartSection += "              ticks: {\n";
                equityChartSection += "                color: '#a0a0a0'\n";
                equityChartSection += "              }\n";
                equityChartSection += "            }\n";
                equityChartSection += "          }\n";
                equityChartSection += "        }\n";
                equityChartSection += "      });\n";
                equityChartSection += "    } catch (e) { console.error('Error initializing equity chart:', e); }\n"; // Catch errors
                equityChartSection += "  });\n";
                equityChartSection += "</script>\n";
            } else {
                equityChartSection = "<div class=\"card\">\n";
                equityChartSection += "<h3>График эквити</h3>\n";
                equityChartSection += "<div class=\"empty-chart-message\">Недостаточно данных для построения графика.</div>\n";
                equityChartSection += "</div>\n";
            }
        } else {
            Print(__FUNCTION__, ": Ошибка получения данных для графика эквити или недостаточно точек.");
            equityChartSection = "<div class=\"card\">\n";
            equityChartSection += "<h3>График эквити</h3>\n";
            equityChartSection += "<div class=\"empty-chart-message\">Не удалось получить данные для графика эквити.</div>\n";
            equityChartSection += "</div>\n";
        }
        
        // Wrap the cumulative symbol PnL chart in a card
        string cumulative_symbol_pnl_chart_section = "<div class=\"card\">\n" + GetCumulativeSymbolPnlChart(reportStartTime, reportEndTime) + "</div>\n";
        
        // Wrap the symbol stats table in a card
        string symbolStatsSection = "<div class=\"card\">\n" + GetSymbolStatsHTMLTable(reportStartTime, reportEndTime) + "</div>\n";
        
        // Wrap the deals history table in a card
        string dealsSection = "<div class=\"card\">\n" + GetDealsHistoryHTML(reportStartTime, reportEndTime) + "</div>\n";

        string fullReport = htmlHeader + 
                            accountSection + 
                            equityChartSection + 
                            cumulative_symbol_pnl_chart_section + 
                            symbolStatsSection + 
                            dealsSection + 
                            "\n</body>\n</html>";

        char report_data_utf8[];
        int report_len = StringToCharArray(fullReport, report_data_utf8, 0, -1, CP_UTF8);
        if(report_len <= 0) {
             Print(__FUNCTION__,": Ошибка конвертации итогового отчета в UTF-8 массив.");
             return false;
        }
        Print(__FUNCTION__,": Итоговый отчет сконвертирован в UTF-8 массив, ", report_len, " байт.");

        int fileHandle = FileOpen(fileName, FILE_WRITE | FILE_BIN); 
        if(fileHandle == INVALID_HANDLE) {
            Print(__FUNCTION__,": Ошибка при открытии файла '",fileName,"' для бинарной записи. Код ошибки=", GetLastError());
            return false;
        }

        ulong written_bytes = FileWriteArray(fileHandle, report_data_utf8, 0, report_len); 
        FileClose(fileHandle); 

        if(written_bytes != (ulong)report_len) {
            Print(__FUNCTION__,": Ошибка записи в файл '", fileName, "'. Ожидалось: ", report_len, ", Записано: ", (string)written_bytes);
            FileDelete(fileName); 
            return false;
        }

        Print(__FUNCTION__,": Запись отчёта с графиком в файл '", fileName, "' завершена успешно. Записано байт: ", (string)written_bytes);
        return true; 
    }

}; // конец пространства имен REPORT