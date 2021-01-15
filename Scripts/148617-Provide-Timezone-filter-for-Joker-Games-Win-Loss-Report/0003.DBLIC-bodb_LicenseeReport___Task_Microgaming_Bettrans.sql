/*<info serverAlias="DBLIC-bodb_LicenseeReport"></info>*/
/*
	Created: 20210113@Parsons
	Task:   Generate data of Joker for 2020-11-12 -> Now [#FeatureID 148617]
	DB:	    DBLIC-bodb_LicenseeReport
	Remark:	Re-gen data for Joker - range bettrans
*/

USE bodb_LicenseeReport
GO

DECLARE 
		@FromDate DATE = '2021-01-11', -- Current MB Date + 1, MB: 2021-01-10
		@ToDate	DATE = '2021-01-15' -- Current Date

BEGIN
	DECLARE @ErrMsg VARCHAR(200)

	DECLARE @WinlostDate DATE
	SELECT	@WinlostDate = @FromDate

	WHILE @WinlostDate <= @ToDate
	BEGIN
		SELECT @ErrMsg = 'WinlostDate=' + CONVERT(VARCHAR(20), @WinlostDate, 120)
		RAISERROR(@ErrMsg, 1, 0) WITH NOWAIT

		EXEC dbo.Task_Microgaming_Bettrans @WinlossDate = @WinlostDate

		--reset params
		SET @WinlostDate = DATEADD(DAY, 1, @WinlostDate)

		WAITFOR DELAY '00:00:00.280'
	END
END
GO