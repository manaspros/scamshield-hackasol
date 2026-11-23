package com.hackasol.scamshield.core

import com.hackasol.scamshield.core.graph.KnowledgeGraph

/** "Delete my data": the shared graph (memory and store) always; the real verdict log only with [alsoAlerts]. Never touches the Demo Lab, which has its own log. */
object DataReset {
    /** True only when everything asked for was deleted; both deletes are always attempted. */
    fun run(graph: KnowledgeGraph, log: VerdictLog?, alsoAlerts: Boolean): Boolean {
        val graphOk = graph.clear()
        val logOk = !alsoAlerts || try { log?.clear(); true } catch (_: Exception) { false }
        return graphOk && logOk
    }
}
