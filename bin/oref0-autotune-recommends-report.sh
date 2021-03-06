#!/bin/bash

# This script creates a Summary Report of Autotune Recommendations. The report itself is
# structured in such a way intended to give the end user a quick look at what needs to change
# on their pump. Report is stored in the autotune sub-directory within the user's OpenAPS
# directory.
#
# Released under MIT license. See the accompanying LICENSE.txt file for
# full terms and conditions
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
# THE SOFTWARE.
#
# Example usage: ~/src/oref0/bin/oref0-autotune-recommends-report.sh <OpenAPS Loop Directory Path>

die() {
  echo "$@"
  exit 1
}

if [ $# -ne 1 ]; then
    echo "Usage: ./oref0-autotune-recommends-report.sh <OpenAPS Loop Directory Path>"
    exit 1
fi

# OpenAPS Directory Input
directory=$1

# Set report filename and delete the old one if it exists
report_file=$directory/autotune/autotune_recommendations.log
[ -f $report_file ] && rm $report_file

# Report Column Widths
parameter_width=15
data_width=9

# Get current profile info
basal_minutes_current=( $(jq -r '.basalprofile[].minutes' $directory/autotune/profile.pump.json) )
basal_rate_current=( $(jq -r '.basalprofile[].rate' $directory/autotune/profile.pump.json) )
isf_current=$(cat $directory/autotune/profile.pump.json | jq '.isfProfile.sensitivities[0].sensitivity')
csf_current=$(cat $directory/autotune/profile.pump.json | jq '.csf')
carb_ratio_current=$(cat $directory/autotune/profile.pump.json | jq '.carb_ratio')

# Get autotune profile info
basal_minutes_new=( $(jq -r '.basalprofile[].minutes' $directory/autotune/profile.json) )
basal_rate_new=( $(jq -r '.basalprofile[].rate' $directory/autotune/profile.json) )
isf_new=$(cat $directory/autotune/profile.json | jq '.isfProfile.sensitivities[0].sensitivity')
csf_new=$(cat $directory/autotune/profile.json | jq '.csf')
carb_ratio_new=$(cat $directory/autotune/profile.json | jq '.carb_ratio')

# Print Header Info
printf "%-${parameter_width}s| %-${data_width}s| %-${data_width}s\n" "Parameter" "Current" "Autotune" >> $report_file
printf "%s\n" "-------------------------------------" >> $report_file

# Print ISF, CSF and Carb Ratio Recommendations
printf "%-${parameter_width}s| %-${data_width}.3f| %-${data_width}.3f\n" "ISF" $isf_current $isf_new >> $report_file
if [ $csf_current != null ]; then
  printf "%-${parameter_width}s| %-${data_width}.3f| %-${data_width}.3f\n" "CSF" $csf_current $csf_new >> $report_file
else
  printf "%-${parameter_width}s| %-${data_width}s| %-${data_width}.3f\n" "CSF" "n/a" $csf_new >> $report_file
fi
printf "%-${parameter_width}s| %-${data_width}.3f| %-${data_width}.3f\n" "Carb Ratio" $carb_ratio_current $carb_ratio_new >> $report_file

# Print Basal Profile Recommendations
printf "%-${parameter_width}s| %-${data_width}s| %-${data_width}s\n" "Basal Profile" "" "" >> $report_file

# Build time_list array of H:M in 30 minute increments to mirror pump basal schedule
time_list=()
minutes_list=()
end_time=23:30
time=00:00
minutes=0
while :
do
  time_list+=( "$time" )
  minutes_list+=( "$minutes" )
  if [ $time != "$end_time" ]; then
    time="$(date --date="$time 30 minutes" +%R)";
    minutes=$(expr $minutes + 30)
  else
    break
  fi
done

for (( i=0; i<${#minutes_list[@]}; i++ ))
do
  # Check for current entry (account for 1-based index from grep)
  basal_index_current=$(printf "%s\n" ${basal_minutes_current[@]}|grep -nw ${minutes_list[$i]} | sed 's/:.*//')
  if [[ ${#basal_index_current} != 0 ]]; then
    rate_current=${basal_rate_current[$(($basal_index_current - 1))]}
  fi
  # Check for autotune entry (account for 1-based index from grep)
  basal_index_new=$(printf "%s\n" ${basal_minutes_new[@]}|grep -nw ${minutes_list[$i]} | sed 's/:.*//')
  if [[ ${#basal_index_new} != 0 ]]; then
    rate_new=${basal_rate_new[$((${basal_index_new} - 1))]}
  fi
  # Print this basal profile recommend based on data availability at this time
  if [[ ${#basal_index_current} == 0 ]] && [[ ${#basal_index_new} == 0 ]]; then
    printf "  %-$(expr ${parameter_width} - 2)s| %-${data_width}s| %-${data_width}s\n" ${time_list[$i]} "" "" >> $report_file
  elif [[ ${#basal_index_current} == 0 ]] && [[ ${#basal_index_new} != 0 ]]; then
    printf "  %-$(expr ${parameter_width} - 2)s| %-${data_width}s| %-${data_width}.3f\n" ${time_list[$i]} "" $rate_new >> $report_file
  elif [[ ${#basal_index_current} != 0 ]] && [[ ${#basal_index_new} == 0 ]]; then
    printf "  %-$(expr ${parameter_width} - 2)s| %-${data_width}s| %-${data_width}s\n" ${time_list[$i]} $rate_current "" >> $report_file
  else
    printf "  %-$(expr ${parameter_width} - 2)s| %-${data_width}.3f| %-${data_width}.3f\n" ${time_list[$i]} $rate_current $rate_new >> $report_file
  fi
done
