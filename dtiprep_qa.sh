#!/bin/bash
#Prepares SIEMENS DTI data for dtiprep

if [ $# -lt 3 ]; then
 echo "Usage: ./dtiprep_qa <nifti_file> <bvecs> <bvals>"
 echo "Usage: ./dtiprep_qa myfile.nii.gz myfile.bvec myfile.bval"
 exit;
fi
if [ ! -e $1 ]; then
 echo "$1 does not exist. Use a real file."
 exit;
fi
if [ ! -e $2 ]; then
 echo "$2 does not exist. Use a real file."
 exit;
fi
if [ ! -e $3 ]; then
 echo "$3 does not exist. Use a real file."
 exit;
fi

LAB_DIR="/mnt/stressdevlab"
PROJECT=`echo ${1} | awk -F "stressdevlab/" '{print $2}' | awk -F "/" '{print $1}'`
PROJECT_DIR="${LAB_DIR}/${PROJECT}"
TMP_DIR=`mktemp -d /tmp/dtiprepXXXX`

if [[ ${PROJECT} == *new_memory* ]] || [[ ${PROJECT} == *dep_threat* ]] || [[ ${PROJECT} == *SAS_DTI* ]] ; then
	SUBJECT=`echo ${1} | awk -F "/" '{print $5}'`
	SUBJECT_DIR=${PROJECT_DIR}/${SUBJECT}
elif [[ ${PROJECT} == *fear_pipeline* ]] || [[ ${PROJECT} == *stress_pipeline* ]]; then
	SUBJECT=`echo ${1} | awk -F "/" '{print $6}'`
	PRESUB=`echo ${1} | awk -F "${SUBJECT}" '{print $1}'`
	SUBJECT_DIR=${PRESUB}/${SUBJECT}
else
	echo "ERROR: Could not determine subject ID number."
	exit 1
fi

echo "Files found, proceeding with Quality Check"

#Create a temporary working space with date & time
foldername=`date +"%m%d%y_%T" | sed 's/://g'`
mkdir ${TMP_DIR}

#Copy over DWI image data and transpose bvals
3dcopy $1 ${TMP_DIR}/dwi.nii
1dtranspose $3 > ${TMP_DIR}/bval.txt

#Transpose b-vectors, flip y gradient b/c Siemens...
1dDW_Grad_o_Mat \
-in_grad_rows $2 \
-out_grad_cols ${TMP_DIR}/bvec.txt \
-flip_y \
-keep_b0s

#Move into temporary working directory
cd ${TMP_DIR}

#Convert DWI image data from NIFTI to NRRD
/usr/local/DTIPrepPackage/DWIConvert \
--inputVolume dwi.nii \
--inputBVectors bvec.txt \
--inputBValues bval.txt \
--conversionMode FSLToNrrd \
-o dwi.nrrd

cp -r ${TMP_DIR} /mnt/stressdevlab/new_memory_pipeline/DTI/TESTTractography
exit

#Run default QA check
/usr/local/DTIPrepPackage/DTIPrep \
-c \
-d \
-p test.xml \
-w dwi.nrrd \
--numberOfThreads 24

#Convert corrected DWI image data from NRRD to NIFTI
/usr/local/DTIPrepPackage/DWIConvert \
--inputVolume dwi_QCed.nrrd \
--outputVolume dwi_QCed.nii \
--outputBVectors dwi_QCed.bvec \
--outputBValues dwi_QCed.bval \
--conversionMode NrrdToFSL

#Echo DTI prep results
echo "Total Good Gradients: `cat dwi_QCed.bvec | wc -l`"

#Save QA data to subject's QA directory
mkdir -p ${SUBJECT_DIR}/QA/DTIPrep
cp -r ${TMP_DIR}/* ${SUBJECT_DIR}/QA/DTIPrep/
cd $current

#QA 
cat ${SUBJECT_DIR}/QA/DTIPrep/dwi_QCReport.txt | sed -n '/Slice-wise\ Check/,/=====================/p' | tee ${SUBJECT_DIR}/QA/DTIPrep/Slice-wiseArtifactDetails.txt
cat ${SUBJECT_DIR}/QA/DTIPrep/Slice-wiseArtifactDetails.txt | awk -F "\t" '{print $2}' | grep [0-9] | uniq | ${LAB_DIR}/scripts/Preprocessing/transpose.awk | tee ${SUBJECT_DIR}/QA/DTIPrep/Slice-wiseArtifactVols.txt

