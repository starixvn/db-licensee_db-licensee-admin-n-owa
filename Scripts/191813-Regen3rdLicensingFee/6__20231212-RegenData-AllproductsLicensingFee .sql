/*<info serverAlias="DBLIC-bodb_licensee"></info>*/
/*
	Created: 20231121@Danny
	DB: DBLIC-bodb_Licensee
	Task: Insert Data 3rd products [#191813]
	-- Run DB053, DB052 only
*/
USE bodb_Licensee
GO

SET NOCOUNT ON 

-- Remove old data 
delete from bodb_LicenseeReport.dbo.rptLicPerformanceAnalysis_regen_UAT with(rowlock)
where ReportDate IN ('2023-09-01','2023-10-01')


-- Regen data using exec SP
DECLARE 
	@FromDate		DATE = '2023-09-01'

DECLARE
	@ToDate			DATE =  EOMONTH(@FromDate)
	

WHILE @ToDate <= '2023-10-31'
BEGIN
	print 'running -----: ' + CAST (@FromDate AS VARCHAR(50)) + '-------' +  CAST (@ToDate AS VARCHAR(50))

	EXEC [dbo].LA_GEN_LicPerformanceAnalysis_Report_xtest
		@FromDate		= @FromDate,
		@ToDate			= @ToDate,
		@Environment	= 'PRO',
		@IsOverwrite	= 1
	

	SELECT @FromDate = DATEADD(MONTH,1,@FromDate)
	SELECT @ToDate	=  EOMONTH(@FromDate)
END

GO


